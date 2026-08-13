/**
 * GitHub PAT 本地配置文件（只在你这台电脑上存在，不会上传到 GitHub）
 *
 * ===== 使用方法 =====
 * 方法一（推荐）：双击项目目录里的「1-写入PAT到本地.bat」按提示粘贴 PAT，自动生成本文件。
 * 方法二：复制本文件改名为 pat.js，把下面的 '' 改成你的 PAT（以 ghp_ 开头的 40 位字符串）。
 *
 * ===== 安全提醒 =====
 * 1. pat.js 已加入 .gitignore，Git 不会提交它，所以不用担心 PAT 泄露到公开仓库；
 * 2. PAT 只保存在你这台电脑的 J:\9178GG\pat.js，和浏览器 localStorage 作用一样，
 *    但好处是 admin.html 打开就自动读取，不用你每次手动粘贴。
 */
window._GH_PAT = ''; // 例：'ghp_AbCdEfGhIjKlMnOpQrStUvWxYz1234567890abcd'
