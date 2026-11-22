/**
 * 跨平台准备本机签名配置与 Git 保护
 *
 * 仓库里的 build-profile.json5 是无签名版本（signingConfigs: []，modules 含
 * main + notes_hsp）；本脚本负责把本机签名物料写进它，并用 skip-worktree
 * 防止本机签名配置被提交。
 *
 * 用法:
 *   node tools/setup_signing.js
 *   node tools/setup_signing.js --from <路径>
 */
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const repoRoot = path.resolve(__dirname, '..');
const target = path.join(repoRoot, 'build-profile.json5');
const localBackup = path.join(repoRoot, 'build-profile.local.json5');
const template = path.join(repoRoot, 'build-profile.template.json5');

function protectProfile() {
  try {
    execSync('git update-index --skip-worktree build-profile.json5', { stdio: 'ignore', cwd: repoRoot });
    console.log('[ OK ] 已设置 git skip-worktree，本地签名不会被 Git 提交。');
  } catch (e) {
    // ignore
  }
}

const args = process.argv.slice(2);
const fromIdx = args.indexOf('--from');
const fromPath = fromIdx !== -1 ? args[fromIdx + 1] : null;

if (fromPath) {
  if (!fs.existsSync(fromPath)) {
    console.error(`[ERROR] 找不到来源文件: ${fromPath}`);
    process.exit(1);
  }
  fs.copyFileSync(fromPath, target);
  protectProfile();
  console.log(`[ OK ] 已从 ${fromPath} 安装本机签名配置`);
  process.exit(0);
}

if (fs.existsSync(localBackup) && (!fs.existsSync(target) || args.includes('--force'))) {
  fs.copyFileSync(localBackup, target);
  protectProfile();
  console.log(`[ OK ] 已从本地备份 ${localBackup} 恢复签名配置`);
  process.exit(0);
}

if (fs.existsSync(target)) {
  protectProfile();
  const text = fs.readFileSync(target, 'utf-8');
  if (/<HOME>|<project>|DevEco 生成的加密口令/.test(text)) {
    console.warn('[WARN] build-profile.json5 仍含模板占位符，请在 DevEco Studio 中自动签名。');
    process.exit(1);
  }
  console.log('[ OK ] build-profile.json5 已就绪。');
  process.exit(0);
}

if (fs.existsSync(template)) {
  fs.copyFileSync(template, target);
  protectProfile();
  console.log('[ OK ] 已从模板生成 build-profile.json5');
  console.log('请在 DevEco Studio 中打开工程并在 Signing Configs 勾选自动签名。');
}
