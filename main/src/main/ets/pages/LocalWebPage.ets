import { HMRouter } from '@hadss/hmrouter';
import { PageNames } from '../constant/PageNames';
import { WebServerUtil } from '../utils/WebServerUtil';
import { BackgroundTaskUtil } from '../utils/BackgroundTaskUtil';
import { FloatWindowUtil } from '../utils/FloatWindowUtil';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { common, bundleManager } from '@kit.AbilityKit';
import { webview } from '@kit.ArkWeb';
import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { BackgroundServiceManager } from '../utils/BackgroundServiceManager';
import { TargetConstants } from 'main/ets/TargetConstants';

// --- 类型定义 ---
interface MenuElement {
  value: string;
  action: () => void;
  enabled?: boolean;
}

class FileItem {
  name: string = "";
  size: number = 0;
  path: string = "";
  relativePath: string = "";
  isDir: boolean = false;
  modTime: number = 0;
  rateLimitMinutes: number = 0; // 新增：保存该文件的当前频控时间
}

class ClipboardItem {
  filePath: string = "";
  fileName: string = "";
  isDir: boolean = false;
  action: 'copy' | 'move' = 'copy';
}

// --- ViewModel ---
@ObservedV2
class WebViewModel {
  @Trace isServerRunning: boolean = false;
  @Trace serverIp: string = "0.0.0.0";
  @Trace serverPort: number = 8088;
  @Trace bundleName: string = "";
  @Trace fileList: FileItem[] = [];
  @Trace currentPath: string = "";
  @Trace isEditing: boolean = false;
  @Trace editingFileContent: string = "";
  @Trace editingFilePath: string = "";
  @Trace editingFileName: string = "";
  @Trace previewUrl: string = "";
  @Trace isPreviewing: boolean = false;
  @Trace clipboard: ClipboardItem | null = null;
  webController: webview.WebviewController = new webview.WebviewController();
  rootDir: string = "";
  phyDirPath: string = "";
}

// --- 主页面 ---
@HMRouter({ pageUrl: PageNames.LOCAL_WEB_PAGE })
@ComponentV2
export struct LocalWebPage {
  @Local viewModel: WebViewModel = new WebViewModel();
  private context = getContext(this) as common.UIAbilityContext;
  private newFolderDialogController: CustomDialogController | null = null;
  private renameDialogController: CustomDialogController | null = null;
  @Local dialogInputName: string = "";
  private renameTargetItem: FileItem | null = null;

  aboutToAppear(): void {
    BackgroundTaskUtil.init(this.context);
    FloatWindowUtil.init(this.context);
    this.viewModel.rootDir = this.context.filesDir + '/wwwroot';
    let bundleName = this.context.applicationInfo.name;
    this.viewModel.phyDirPath = `/data/app/el2/100/base/${bundleName}/haps/main/files/wwwroot`;

    try {
      bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).then((data) => {
        this.viewModel.bundleName = data.name;
      });
    } catch (e) {
    }

    let server = WebServerUtil.getInstance();
    server.init(this.viewModel.rootDir, this.viewModel.serverPort);
    if (server.isRunning) {
      this.viewModel.isServerRunning = true;
      this.viewModel.serverIp = server.getIpAddress();
    }
    this.refreshFileList();
  }

  // --- 逻辑部分 ---
  refreshFileList(): void {
    try {
      let fullCurrentPath = this.viewModel.rootDir + this.viewModel.currentPath;
      if (!fs.accessSync(fullCurrentPath)) {
        fs.mkdirSync(fullCurrentPath, true);
      }

      let filenames = fs.listFileSync(fullCurrentPath);
      let items: FileItem[] = [];
      let server = WebServerUtil.getInstance(); // 获取 Server 实例读取频控

      filenames.forEach((name) => {
        let path = fullCurrentPath + '/' + name;
        try {
          let stat = fs.statSync(path);
          items.push({
            name: name,
            size: stat.size,
            path: path,
            relativePath: (this.viewModel.currentPath === "" ? "" : this.viewModel.currentPath + "/") + name,
            isDir: stat.isDirectory(),
            modTime: stat.mtime,
            rateLimitMinutes: stat.isDirectory() ? 0 : server.getRateLimitMinutes(path) // 读取频控分钟数
          });
        } catch (e) {
        }
      });

      items.sort((a, b) => {
        if (a.isDir && !b.isDir) {
          return -1;
        }
        if (!a.isDir && b.isDir) {
          return 1;
        }
        return a.name.localeCompare(b.name);
      });
      this.viewModel.fileList = items;
    } catch (e) {
      promptAction.showToast({ message: "刷新失败" });
    }
  }

  openRenameDialog(item: FileItem): void {
    this.renameTargetItem = item;
    this.dialogInputName = item.name;
    this.renameDialogController?.open();
  }

  execRename(): void {
    if (!this.renameTargetItem || !this.dialogInputName) {
      return;
    }
    try {
      let newPath = this.viewModel.rootDir + this.viewModel.currentPath + '/' + this.dialogInputName;
      if (fs.accessSync(newPath)) {
        promptAction.showToast({ message: "名称已存在" });
        return;
      }
      fs.renameSync(this.renameTargetItem.path, newPath);
      this.refreshFileList();
    } catch (e) {
    }
  }

  addToClipboard(item: FileItem, action: 'copy' | 'move'): void {
    this.viewModel.clipboard = {
      filePath: item.path,
      fileName: item.name,
      isDir: item.isDir,
      action: action
    };
    promptAction.showToast({ message: action === 'copy' ? "已复制" : "已准备移动" });
  }

  execPaste(): void {
    if (!this.viewModel.clipboard) {
      return;
    }
    const clip = this.viewModel.clipboard;
    let destPath = this.viewModel.rootDir + this.viewModel.currentPath + '/' + clip.fileName;

    if (destPath.startsWith(clip.filePath + '/')) {
      promptAction.showToast({ message: "无法粘贴到源文件夹内" });
      return;
    }

    if (fs.accessSync(destPath)) {
      let counter = 1;
      let originalName = clip.fileName;
      while (fs.accessSync(destPath)) {
        let dotIndex = originalName.lastIndexOf('.');
        let name = dotIndex > -1 ? originalName.substring(0, dotIndex) : originalName;
        let ext = dotIndex > -1 ? originalName.substring(dotIndex) : "";
        destPath = this.viewModel.rootDir + this.viewModel.currentPath + '/' + `${name}(${counter})${ext}`;
        counter++;
      }
    }

    try {
      if (clip.action === 'move') {
        fs.renameSync(clip.filePath, destPath);
        this.viewModel.clipboard = null;
      } else {
        clip.isDir ? this.copyDirRecursive(clip.filePath, destPath) : fs.copyFileSync(clip.filePath, destPath);
      }
      this.refreshFileList();
      promptAction.showToast({ message: "操作成功" });
    } catch (e) {
      promptAction.showToast({ message: "操作失败" });
    }
  }

  copyDirRecursive(src: string, dest: string): void {
    if (!fs.accessSync(dest)) {
      fs.mkdirSync(dest);
    }
    let files = fs.listFileSync(src);
    for (let file of files) {
      let srcPath = src + '/' + file;
      let destPath = dest + '/' + file;
      let stat = fs.statSync(srcPath);
      stat.isDirectory() ? this.copyDirRecursive(srcPath, destPath) : fs.copyFileSync(srcPath, destPath);
    }
  }

  duplicateItem(item: FileItem): void {
    try {
      let destPath = "";
      let counter = 1;
      let originalName = item.name;
      let dotIndex = originalName.lastIndexOf('.');
      let name = dotIndex > -1 ? originalName.substring(0, dotIndex) : originalName;
      let ext = dotIndex > -1 ? originalName.substring(dotIndex) : "";

      do {
        let suffix = counter === 1 ? "_copy" : `_copy(${counter})`;
        destPath = this.viewModel.rootDir + this.viewModel.currentPath + '/' + `${name}${suffix}${ext}`;
        counter++;
      } while (fs.accessSync(destPath));

      item.isDir ? this.copyDirRecursive(item.path, destPath) : fs.copyFileSync(item.path, destPath);
      this.refreshFileList();
    } catch (e) {
    }
  }

  async importFiles(): Promise<void> {
    try {
      let documentPicker = new picker.DocumentViewPicker();
      let result = await documentPicker.select({ maxSelectNumber: 10 });
      if (result.length > 0) {
        result.forEach((uri) => {
          try {
            let originalName = "file";
            try {
              originalName = decodeURIComponent(uri).split('/').pop() || "file";
            } catch (e) {
            }
            let file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
            let destPath = this.viewModel.rootDir + this.viewModel.currentPath + '/' + originalName;
            let counter = 1;
            while (fs.accessSync(destPath)) {
              let dotIndex = originalName.lastIndexOf('.');
              let name = dotIndex > -1 ? originalName.substring(0, dotIndex) : originalName;
              let ext = dotIndex > -1 ? originalName.substring(dotIndex) : "";
              destPath = this.viewModel.rootDir + this.viewModel.currentPath + '/' + `${name}(${counter})${ext}`;
              counter++;
            }
            fs.copyFileSync(file.fd, destPath);
            fs.closeSync(file);
          } catch (e) {
          }
        });
        this.refreshFileList();
      }
    } catch (e) {
    }
  }

  createFolder(): void {
    if (!this.dialogInputName) {
      return;
    }
    try {
      let path = this.viewModel.rootDir + this.viewModel.currentPath + '/' + this.dialogInputName;
      if (!fs.accessSync(path)) {
        fs.mkdirSync(path);
      }
      this.refreshFileList();
    } catch (e) {
    }
  }

  deleteItem(item: FileItem): void {
    try {
      item.isDir ? this.deleteRecursive(item.path) : fs.unlinkSync(item.path);
      this.refreshFileList();
    } catch (e) {
    }
  }

  private deleteRecursive(path: string): void {
    if (fs.statSync(path).isDirectory()) {
      fs.listFileSync(path).forEach(f => {
        let p = path + "/" + f;
        fs.statSync(p).isDirectory() ? this.deleteRecursive(p) : fs.unlinkSync(p);
      });
      fs.rmdirSync(path);
    } else {
      fs.unlinkSync(path);
    }
  }

  toggleServer(): void {
    let server = WebServerUtil.getInstance();
    if (this.viewModel.isServerRunning) {
      server.stop();
      this.viewModel.isServerRunning = false;
      if (TargetConstants.HAS_FLOATING_PERM) {
        FloatWindowUtil.destroyFloatWindow();
      }
      BackgroundServiceManager.stopWebServer();
    } else {
      server.start().then(() => {
        this.viewModel.isServerRunning = true;
        this.viewModel.serverIp = server.getIpAddress();
        if (TargetConstants.HAS_FLOATING_PERM) {
          FloatWindowUtil.showFloatWindow();
        }
        BackgroundServiceManager.startWebServer(this.viewModel.serverIp)
      }).catch((err: Object) => {
      });
    }
  }

  enterFolder(item: FileItem): void {
    this.viewModel.currentPath = this.viewModel.currentPath + "/" + item.name;
    this.refreshFileList();
  }

  goBack(): void {
    let path = this.viewModel.currentPath;
    if (path === "") {
      return;
    }
    let lastSlash = path.lastIndexOf('/');
    this.viewModel.currentPath = lastSlash <= 0 ? "" : path.substring(0, lastSlash);
    this.refreshFileList();
  }

  showHdcGuide(): void {
    let remotePath = `${this.viewModel.phyDirPath}\/`;
    if (this.viewModel.currentPath !== "") {
      remotePath += this.viewModel.currentPath.substring(1) + "/";
    }
    let command = `hdc file send "local_file" "${remotePath}"`;

    let devMessage =
      `调试路径：\n${remotePath}\n\n示例：\n${command}\n\nHDC推送场景需要授予权限：\nhdc shell chmod 777 -R ${this.viewModel.phyDirPath}\/`;
    let message = `由于鸿蒙系统机制，可能后台无法常驻;\n如出现，建议使用小窗模式运行;\n或联系作者通过调试证书安装。`;
    promptAction.showDialog({
      title: 'web服务常驻说明', message: TargetConstants.IS_AG_TARGET ? message : devMessage,
      buttons: [{ text: '关闭', color: '#666' }, { text: 'ok', color: '#007DFF' }]
    }).then(resp => {
      if (resp.index === 1) {
        let data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, remotePath);
        pasteboard.getSystemPasteboard().setData(data);
        promptAction.showToast({ message: "理解万岁~" });
      }
    });
  }

  canEdit(name: string): boolean {
    const exts = ['.txt', '.json', '.html', '.css', '.js', '.md', '.xml', '.ts', '.ets'];
    return exts.some(ext => name.toLowerCase().endsWith(ext));
  }

  openEditor(item: FileItem): void {
    try {
      this.viewModel.editingFileContent = fs.readTextSync(item.path);
      this.viewModel.editingFilePath = item.path;
      this.viewModel.editingFileName = item.name;
      this.viewModel.isEditing = true;
    } catch (e) {
      promptAction.showToast({ message: "读取失败" });
    }
  }

  saveFile(): void {
    try {
      let file = fs.openSync(this.viewModel.editingFilePath, fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, this.viewModel.editingFileContent);
      fs.closeSync(file);
      promptAction.showToast({ message: "保存成功" });
      this.viewModel.isEditing = false;
      this.refreshFileList();
    } catch (e) {
      promptAction.showToast({ message: "保存失败" });
    }
  }

  openPreview(item: FileItem): void {
    if (!this.viewModel.isServerRunning) {
      this.toggleServer();
    }
    let relative = this.viewModel.currentPath;
    if (relative.startsWith('/')) {
      relative = relative.substring(1);
    }
    let path = relative ? `${relative}/${item.name}` : item.name;
    this.viewModel.previewUrl = `http://127.0.0.1:${this.viewModel.serverPort}/${path}`;
    this.viewModel.isPreviewing = true;
  }

  // --- 新增：展示频控菜单 ---
  showRateLimitMenu(item: FileItem): void {
    promptAction.showActionMenu({
      title: `设置访问频控: \n${item.name}`,
      buttons: [
        { text: '无频控', color: '#007DFF' },
        { text: '1分钟', color: '#007DFF' },
        { text: '3分钟', color: '#007DFF' },
        { text: '5分钟', color: '#007DFF' },
        { text: '10分钟', color: '#007DFF' },
        { text: '30分钟', color: '#007DFF' }
      ]
    }).then(data => {
      const minutesMap: Record<number, number> = {
        0: 0, 1: 1, 2: 3, 3: 5, 4: 10, 5: 30
      };
      if (data.index >= 0 && data.index <= 5) {
        let minutes = minutesMap[data.index];
        WebServerUtil.getInstance().setRateLimit(item.path, minutes);

        this.refreshFileList(); // 设置完成后刷新列表状态

        if (minutes === 0) {
          promptAction.showToast({ message: "已取消该文件的频控限制" });
        } else {
          promptAction.showToast({ message: `已设置成功，冷却时间：${minutes}分钟` });
        }
      }
    }).catch((err: Error) => {
      console.info("ActionMenu canceled");
    });
  }

  getMenuItems(item: FileItem): MenuElement[] {
    let menus: MenuElement[] = [];
    if (!item.isDir && this.canEdit(item.name)) {
      menus.push({ value: '编辑代码', action: () => this.openEditor(item) });
    }

    // 如果是普通文件，允许设置访问频控
    if (!item.isDir) {
      menus.push({ value: '设置频控', action: () => this.showRateLimitMenu(item) });
    }

    menus.push({ value: '重命名', action: () => this.openRenameDialog(item) });
    menus.push({ value: '创建副本', action: () => this.duplicateItem(item) });
    menus.push({ value: '复制', action: () => this.addToClipboard(item, 'copy') });
    menus.push({ value: '移动 (剪切)', action: () => this.addToClipboard(item, 'move') });
    menus.push({
      value: '删除',
      action: () => {
        promptAction.showDialog({
          title: '删除', message: `确认删除 ${item.name}?`,
          buttons: [{ text: '取消', color: '#666' }, { text: '删除', color: '#F00' }]
        }).then(r => {
          if (r.index === 1) {
            this.deleteItem(item)
          }
        })
      }
    });
    return menus;
  }

  // --- UI 构建 ---

  @Builder
  InputDialog(title: string, onConfirm: () => void) {
    Column() {
      Text(title).fontSize(18).fontWeight(FontWeight.Bold).margin({ bottom: 15 })
      TextInput({ placeholder: "请输入名称", text: this.dialogInputName })
        .onChange((val) => {
          this.dialogInputName = val;
        })
        .width('100%').margin({ bottom: 20 })
      Row() {
        Button("取消")
          .backgroundColor('#F5F5F5')
          .fontColor('#666')
          .onClick(() => {
            this.newFolderDialogController?.close();
            this.renameDialogController?.close();
          })
          .layoutWeight(1)
          .margin({ right: 10 })
        Button("确定").backgroundColor('#007DFF')
          .onClick(() => {
            onConfirm();
            this.newFolderDialogController?.close();
            this.renameDialogController?.close();
          })
          .layoutWeight(1)
      }.width('100%')
    }.padding(20).backgroundColor($r('sys.color.ohos_id_color_background'))
  }

  @Builder
  HeaderSection() {
    Column() {
      Row() {
        Column() {
          Row() {
            Text(this.viewModel.isServerRunning ? "服务运行中" : "服务已停止")
              .fontWeight(FontWeight.Bold)
              .fontColor(this.viewModel.isServerRunning ? $r('sys.color.ohos_id_color_connected') :
                $r('sys.color.ohos_id_color_warning'))
            Button("?")
              .width(20)
              .height(20)
              .padding(0)
              .fontSize(12)
              .margin({ left: 8 })
              .backgroundColor($r('sys.color.ohos_id_color_tertiary'))
              .fontColor($r('sys.color.ohos_id_color_text_primary'))
              .onClick(() => this.showHdcGuide())
          }

          if (this.viewModel.isServerRunning) {
            Text(`http://${this.viewModel.serverIp}:${this.viewModel.serverPort}`)
              .fontSize(14)
              .fontColor($r('sys.color.ohos_id_color_text_secondary'))
              .margin({ top: 4 })
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)

        Toggle({ type: ToggleType.Switch, isOn: this.viewModel.isServerRunning }).onChange(() => this.toggleServer())
      }.padding(16).backgroundColor($r('sys.color.ohos_id_color_card_bg')).borderRadius(12).margin(16)
    }
  }

  @Builder
  OperationSection() {
    Column() {
      Row() {
        Image($r('app.media.back_arrow'))
          .width(20)
          .height(20)
          .fillColor($r('sys.color.ohos_id_color_text_primary'))
          .visibility(this.viewModel.currentPath === "" ? Visibility.None : Visibility.Visible)
          .onClick(() => this.goBack())
          .margin({ right: 8 })
        Text(this.viewModel.currentPath === "" ? "根目录" : `...${this.viewModel.currentPath}`)
          .fontSize(16)
          .fontWeight(FontWeight.Medium)
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      .padding({
        left: 16,
        right: 16,
        top: 12,
        bottom: 8
      })

      Row() {
        Button("导入").fontSize(13).height(32).margin({ right: 10 }).onClick(() => this.importFiles())
        Button("建文件夹").fontSize(13).height(32).margin({ right: 10 }).onClick(() => {
          this.dialogInputName = "";
          this.newFolderDialogController?.open();
        })
        Blank()
        Button("刷新").fontSize(13).height(32).onClick(() => this.refreshFileList())
      }.width('100%').padding({ left: 16, right: 16, bottom: 12 })
    }
  }

  @Builder
  FileListSection() {
    List() {
      ForEach(this.viewModel.fileList, (item: FileItem) => {
        ListItem() {
          Row() {
            Row() {
              Text(item.isDir ? "📂" : (item.name.endsWith('.json') ? "{ }" : "📄")).fontSize(24).margin({ right: 12 })
              Column() {
                Text(item.name).fontSize(16).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })

                // --- 显示文件大小与频控标签 ---
                Row() {
                  Text(item.isDir ? "文件夹" : (item.size / 1024).toFixed(1) + " KB")
                    .fontSize(12)
                    .fontColor($r('sys.color.ohos_id_color_text_secondary'))

                  // 如果有频控且不是文件夹，展示橙色小标签
                  if (!item.isDir && item.rateLimitMinutes > 0) {
                    Text(`⏱️ ${item.rateLimitMinutes}分钟`)
                      .fontSize(10)
                      .fontColor('#FF9800')
                      .backgroundColor('#FFF3E0')
                      .padding({ left: 4, right: 4, top: 1, bottom: 1 })
                      .borderRadius(4)
                      .margin({ left: 8 })
                  }
                }.alignItems(VerticalAlign.Center).margin({ top: 4 })

              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            }
            .layoutWeight(1)
            .onClick(() => {
              item.isDir ? this.enterFolder(item) : this.openPreview(item)
            })

            Button("⚙️")
              .type(ButtonType.Normal)
              .fontSize(22)
              .backgroundColor(Color.Transparent)
              .padding(0)
              .width(40)
              .height(40)
              .bindMenu(this.getMenuItems(item))
          }
          .padding(12).width('100%')
          .backgroundColor($r('sys.color.ohos_id_color_background'))
        }
      })
      if (this.viewModel.fileList.length === 0) {
        ListItem() {
          Text("空文件夹")
            .fontSize(14)
            .fontColor('#999')
            .width('100%')
            .textAlign(TextAlign.Center)
            .padding(20)
        }
      }
    }.layoutWeight(1).divider({ strokeWidth: 1, color: $r('sys.color.ohos_id_color_list_separator') })
  }

  @Builder
  EditorLayer() {
    Column() {
      Row() {
        Button("取消")
          .fontColor($r('sys.color.ohos_id_color_text_secondary'))
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            this.viewModel.isEditing = false;
          })
        Text(`编辑: ${this.viewModel.editingFileName}`)
          .fontWeight(FontWeight.Bold)
          .layoutWeight(1)
          .textAlign(TextAlign.Center)
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Button("保存").fontColor('#007DFF').backgroundColor(Color.Transparent).onClick(() => {
          this.saveFile();
        })
      }.height(56).width('100%').border({ width: { bottom: 1 }, color: $r('sys.color.ohos_id_color_list_separator') })

      TextArea({ text: this.viewModel.editingFileContent })
        .onChange((val) => {
          this.viewModel.editingFileContent = val;
        })
        .layoutWeight(1)
        .width('100%')
        .fontFamily('Monospace')
        .fontSize(14)
        .padding(12)
        .backgroundColor($r('sys.color.ohos_id_color_background'))
        .fontColor($r('sys.color.ohos_id_color_text_primary'))
    }.position({ x: 0, y: 0 }).zIndex(200).backgroundColor($r('sys.color.ohos_id_color_background'))
  }

  @Builder
  PreviewLayer() {
    Column() {
      Row() {
        Text("Web 预览")
          .fontWeight(FontWeight.Bold)
          .margin({ left: 16 })
          .fontColor($r('sys.color.ohos_id_color_text_primary'))
        Blank()
        Button("关闭").onClick(() => {
          this.viewModel.isPreviewing = false;
        }).backgroundColor(Color.Transparent).fontColor($r('sys.color.ohos_id_color_text_primary'))
      }.height(50).width('100%').border({ width: { bottom: 1 }, color: $r('sys.color.ohos_id_color_list_separator') })

      Web({ src: this.viewModel.previewUrl, controller: this.viewModel.webController }).layoutWeight(1).width('100%')
    }.position({ x: 0, y: 0 }).zIndex(100).backgroundColor($r('sys.color.ohos_id_color_background'))
  }

  build() {
    NavDestination() {
      Stack() {
        Column() {
          this.HeaderSection()
          Divider().color($r('sys.color.ohos_id_color_list_separator'))
          this.OperationSection()

          if (this.viewModel.clipboard) {
            Row() {
              Text(`已选择: ${this.viewModel.clipboard.fileName} (${this.viewModel.clipboard.action === 'move' ?
                '移动' : '复制'})`)
                .fontSize(12)
                .fontColor(Color.White)
                .layoutWeight(1)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
              Button("取消")
                .fontSize(12)
                .height(24)
                .backgroundColor('#FFFFFF')
                .fontColor('#007DFF')
                .margin({ right: 8 })
                .onClick(() => this.viewModel.clipboard = null)
              Button("粘贴到此处")
                .fontSize(12)
                .height(24)
                .backgroundColor('#FFFFFF')
                .fontColor('#007DFF')
                .onClick(() => this.execPaste())
            }
            .width('100%')
            .padding({
              left: 16,
              right: 16,
              top: 8,
              bottom: 8
            })
            .backgroundColor('#007DFF')
          }

          this.FileListSection()
        }
        .height('100%').width('100%')
        .backgroundColor($r('sys.color.ohos_id_color_sub_background'))

        if (this.viewModel.isEditing) {
          this.EditorLayer()
        }
        if (this.viewModel.isPreviewing) {
          this.PreviewLayer()
        }
      }
    }
    .title("超熵实验室 Web")
    .backgroundColor($r('sys.color.ohos_id_color_sub_background'))
    .onReady((context: NavDestinationContext) => {
      this.newFolderDialogController = new CustomDialogController({
        builder: () => {
          this.InputDialog("新建文件夹", () => this.createFolder())
        },
        alignment: DialogAlignment.Center
      });
      this.renameDialogController = new CustomDialogController({
        builder: () => {
          this.InputDialog("重命名", () => this.execRename())
        },
        alignment: DialogAlignment.Center
      });
    })
  }
}