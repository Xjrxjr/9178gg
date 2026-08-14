// Node.js (修复线上 remote_data.json 的双重 UTF-8 损坏并保存 data_fixed.json UTF-8)
// 运行方法: 打开 cmd -> cd /d J:\9178GG -> node _fix_utf8_double.js
const fs = require('fs');
const path = require('path');
const inFile = path.join(__dirname, 'remote_data.json');
const outFile = path.join(__dirname, 'data_fixed.json');
const src = fs.readFileSync(inFile);

// 双重编码修复 (byte-level)：
// 字节模式是 C2/C3 开头后跟 80..BF 的2字节组，还原为 1 字节的原始 UTF-8 字节
const out = Buffer.alloc(src.length);
let j = 0;
for (let i = 0; i < src.length; i++) {
  const b1 = src[i];
  if ((b1 === 0xC2 || b1 === 0xC3) && i + 1 < src.length && (src[i + 1] & 0xC0) === 0x80) {
    const b2 = src[++i];
    const decoded = b1 === 0xC2 ? b2 : (0xC0 + (b2 & 0x3F));
    out[j++] = decoded;
  } else {
    out[j++] = b1;
  }
}
const final = out.slice(0, j);
// Pretty print JSON for readability + UTF-8 无 BOM
let text = final.toString('utf8');
try {
  const obj = JSON.parse(text);
  text = JSON.stringify(obj, null, 2);
  console.log('✓ JSON 解析并格式化 OK, 条目数=', Array.isArray(obj) ? obj.length : '非数组');
} catch (e) {
  console.log('✗ JSON parse failed, 保留原文:', e.message);
}
fs.writeFileSync(outFile, text, { encoding: 'utf8' });
console.log(`✓ 已写 ${outFile} (${Buffer.byteLength(text,'utf8')} bytes, 原 ${src.length} bytes)`);
console.log('--- 抽样前 500 字符 ---');
console.log(text.slice(0, 500));
