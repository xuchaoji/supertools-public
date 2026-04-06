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

        // 【核心修改】假设 'dev' 或 'default' 是不需要这些敏感权限的目标产物
        // 'pro' 目标因为需要这些权限，所以直接放行，不做拦截
        if (targetName !== 'dev') {
          node.registerTask({
            name: `${targetName}@removeUnusedPermissions`,
            run() {
              const possiblePaths = [
                path.join(modulePath, 'build', 'default', 'intermediates', 'package', targetName, 'module.json'),
                path.join(modulePath, 'build', targetName, 'intermediates', 'package', targetName, 'module.json')
              ];

              let moduleJsonPath = '';
              for (const p of possiblePaths) {
                if (fs.existsSync(p)) {
                  moduleJsonPath = p;
                  break;
                }
              }

              if (moduleJsonPath) {
                const fileContent = fs.readFileSync(moduleJsonPath, 'utf-8');
                const moduleJson = JSON.parse(fileContent);

                if (moduleJson.module.requestPermissions && moduleJson.module.requestPermissions.length > 0) {

                  // 定义需要在这个 Target 中移除的权限名单
                  const permissionsToRemove = [
                    "ohos.permission.SYSTEM_FLOAT_WINDOW"
                  ];

                  // 过滤掉名单中的权限 (留下不需要移除的)
                  const originalCount = moduleJson.module.requestPermissions.length;
                  moduleJson.module.requestPermissions = moduleJson.module.requestPermissions.filter(
                    (perm: any) => !permissionsToRemove.includes(perm.name)
                  );
                  const newCount = moduleJson.module.requestPermissions.length;

                  // 重新写回文件
                  fs.writeFileSync(moduleJsonPath, JSON.stringify(moduleJson, null, 2));
                  console.log(`\n[CustomPlugin] ✂️ 成功从 Target: [${targetName}] 中移除了 ${originalCount - newCount} 个不需要的权限！\n`);
                }
              } else {
                console.error(`\n[CustomPlugin] 写入失败：未找到 module.json 中间产物。\n`);
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