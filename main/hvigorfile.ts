import { hapTasks, OhosHapContext, OhosPluginId, Target } from '@ohos/hvigor-ohos-plugin';
import { HvigorNode, HvigorPlugin } from '@ohos/hvigor';
import * as fs from 'fs';
import * as path from 'path';

function removePermissionPlugin(): HvigorPlugin {
  return {
    pluginId: 'removePermissionPlugin',
    apply(node: HvigorNode) {
      const hapContext = node.getContext(OhosPluginId.OHOS_HAP_PLUGIN) as OhosHapContext;
      if (!hapContext) return;

      const modulePath = node.getNodePath();

      hapContext.targets((target: Target) => {
        const targetName = target.getTargetName();

        // 只对非 dev 目标（product/default/release 等）移除敏感权限，dev 目标保留悬浮窗权限
        if (targetName !== 'dev') {
          node.registerTask({
            name: `${targetName}@removeUnusedPermissions`,
            run() {
              const permissionsToRemove = [
                "ohos.permission.SYSTEM_FLOAT_WINDOW"
              ];

              // 不硬编码 build 目录名：遍历 build/ 下所有产品目录（default/dev/release/…），
              // 找到该 target 的 module.json 并逐个移除权限，兼容任意产品名。
              const baseDir = path.join(modulePath, 'build');
              let found = false;

              if (fs.existsSync(baseDir)) {
                for (const dir of fs.readdirSync(baseDir)) {
                  const candidate = path.join(baseDir, dir, 'intermediates', 'package', targetName, 'module.json');
                  if (!fs.existsSync(candidate)) {
                    continue;
                  }
                  found = true;

                  const fileContent = fs.readFileSync(candidate, 'utf-8');
                  const moduleJson = JSON.parse(fileContent);

                  if (moduleJson.module && moduleJson.module.requestPermissions && moduleJson.module.requestPermissions.length > 0) {
                    const originalCount = moduleJson.module.requestPermissions.length;
                    moduleJson.module.requestPermissions = moduleJson.module.requestPermissions.filter(
                      (perm: any) => !permissionsToRemove.includes(perm.name)
                    );
                    const removed = originalCount - moduleJson.module.requestPermissions.length;

                    fs.writeFileSync(candidate, JSON.stringify(moduleJson, null, 2));
                    console.log(`\n[CustomPlugin] ✂️ 从 ${candidate} 中移除了 ${removed} 个权限（${permissionsToRemove.join(', ')}）\n`);
                  }
                }
              }

              if (!found) {
                console.error(`\n[CustomPlugin] 写入失败：未找到 ${targetName} 的 module.json 中间产物。\n`);
              }
            },
            dependencies: [`${targetName}@GeneratePkgModuleJson`],
            postDependencies: [`${targetName}@PackageHap`]
          });
        }
      });
    }
  }
}

export default {
  system: hapTasks,
  plugins:[removePermissionPlugin()]
}