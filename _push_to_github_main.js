// Node.js: 用 GitHub API 直接把 3 个 UTF-8 文件推到 main 分支
// 运行: cd J:\9178GG -> node _push_to_github_main.js
// PAT 输入优先级: 1) args --pat=xxx  2) 文件 _pat.txt  3) 命令行交互询问
const fs = require('fs');
const path = require('path');
const https = require('https');
const readline = require('readline');

const OWNER = 'Xjrxjr';
const REPO  = '9178gg';
const BRANCH = 'main';
const FILES = ['index.html', 'data.json', 'admin.html'];
// 上传用的 data.json 用修复后的 data_fixed.json (替代原 data.json)
const MAP_FILE = { 'data.json': 'data_fixed.json' };

function gh(method, path, body) {
  return new Promise((resolve, reject) => {
    const req = https.request({
      hostname: 'api.github.com',
      port: 443,
      method, path,
      headers: {
        'Accept': 'application/vnd.github+json',
        'Authorization': 'Bearer ' + PAT,
        'X-GitHub-Api-Version': '2022-11-28',
        'Content-Type': 'application/json',
        'User-Agent': '9178gg-push-v1'
      }, timeout: 45000
    }, (res) => {
      let data = '';
      res.on('data', c => data += c);
      res.on('end', () => resolve({ status: res.statusCode, body: data }));
    });
    req.on('error', reject);
    if (body) req.write(body);
    req.end();
  });
}
function ghGet(p) { return gh('GET', p); }
function ghPut(p, body) { return gh('PUT', p, body); }

function getSha(path) {
  return ghGet(`/repos/${OWNER}/${REPO}/contents/${encodeURIComponent(path)}?ref=${BRANCH}`)
  .then(r => {
    if (r.status === 404) return '';
    if (r.status !== 200) throw new Error(`GET ${path} HTTP ${r.status} ${r.body.slice(0,400)}`);
    try { return JSON.parse(r.body).sha || ''; } catch (e) { return ''; }
  });
}
function upload(githubPath, localFile, sha) {
  const raw = fs.readFileSync(localFile);
  const b64 = raw.toString('base64');
  const msg = `修复乱码 源头写回 UTF-8: ${githubPath} (${new Date().toISOString().slice(0,16)})`;
  const payload = JSON.stringify({
    message: msg, content: b64, branch: BRANCH, ...(sha ? { sha } : {})
  });
  return ghPut(`/repos/${OWNER}/${REPO}/contents/${encodeURIComponent(githubPath)}`, payload)
  .then(r => {
    if (r.status < 200 || r.status > 299) throw new Error(`PUT ${githubPath} HTTP ${r.status} ${r.body.slice(0,600)}`);
    return r;
  });
}
function question(text) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise(res => rl.question(text, a => { rl.close(); res(a); }));
}

let PAT = '';
async function main() {
  // 1. 获取 PAT
  for (const a of process.argv) if (a.startsWith('--pat=')) PAT = a.slice('--pat='.length).trim();
  const patTxt = path.join(__dirname, '_pat.txt');
  if (!PAT && fs.existsSync(patTxt)) {
    PAT = (fs.readFileSync(patTxt, 'utf8') || '').trim();
    if (PAT) console.log('💡 使用已保存的 PAT (', PAT.length, ' 字符)，如需更换请删除 _pat.txt 或传 --pat=xxx');
  }
  if (!PAT) PAT = (await question('请输入 GitHub PAT (ghp_ 开头，classic token 需勾选 repo): ')).trim();
  if (!PAT) { console.error('❌ 没提供 PAT，退出'); process.exit(2); }
  if (!fs.existsSync(patTxt)) { try { fs.writeFileSync(patTxt, PAT, 'utf8'); console.log('💾 PAT 已保存到 _pat.txt'); } catch(e){} }

  // 2. 校验身份 + 仓库权限
  console.log('🔐 验证 PAT 身份...');
  let r = await ghGet('/user');
  if (r.status !== 200) {
    console.error('❌ PAT 身份错误 HTTP', r.status, r.body.slice(0,300));
    process.exit(3);
  }
  const user = JSON.parse(r.body);
  console.log('  登录为 @' + user.login);

  console.log('📁 验证仓库 ' + OWNER + '/' + REPO + ' @ ' + BRANCH);
  r = await ghGet(`/repos/${OWNER}/${REPO}`);
  if (r.status !== 200) { console.error('❌ 仓库不可访问 HTTP', r.status, r.body.slice(0,300)); process.exit(4); }
  const repoInfo = JSON.parse(r.body);
  console.log('  default_branch=', repoInfo.default_branch, 'private=', repoInfo.private);

  // 3. 循环上传每个文件
  let ok = 0, fail = 0;
  for (const f of FILES) {
    const localSrc = MAP_FILE[f] || f;
    const localPath = path.join(__dirname, localSrc);
    if (!fs.existsSync(localPath)) { console.log(`⏭️  ${f} 本地缺失,跳过`); fail++; continue; }
    process.stdout.write(`⬆️  上传 ${f} (${localSrc}) ...`);
    try {
      const sha = await getSha(f);
      await upload(f, localPath, sha);
      console.log('  ✅ HTTP 200, sha=' + sha.slice(0,8));
      ok++;
    } catch (e) {
      console.log('  ❌ ' + e.message);
      fail++;
    }
  }
  console.log('\n✅ 完成：成功 ' + ok + '，失败 ' + fail);
  if (fail === 0) console.log('等待 GitHub Pages 发布 1-2 分钟后刷新 https://xjrxjr.github.io/9178gg/index.html 即可看到正确中文。');
}
main().catch(e => { console.error('FATAL:', e); process.exit(99); });
