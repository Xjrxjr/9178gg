const DEFAULT_REPOSITORY = 'Xjrxjr/9178gg';
const DEFAULT_ORIGIN = 'https://xjrxjr.github.io';
const DEFAULT_LABEL = 'join-application';
const COACH_LABEL = 'coach-register';

function json(body, status, origin) {
  const headers = {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store'
  };
  if (origin) {
    headers['Access-Control-Allow-Origin'] = origin;
    headers['Vary'] = 'Origin';
  }
  return new Response(JSON.stringify(body), { status, headers });
}

function allowedOrigin(requestOrigin, env) {
  if (!requestOrigin) return '';
  const configured = String(env.ALLOWED_ORIGIN || DEFAULT_ORIGIN)
    .split(',')
    .map((item) => item.trim().replace(/\/+$/, ''))
    .filter(Boolean);
  const normalized = requestOrigin.replace(/\/+$/, '');
  if (configured.includes(normalized)) return requestOrigin;
  if (/^http:\/\/(127\.0\.0\.1|localhost)(:\d+)?$/.test(normalized)) return requestOrigin;
  return '';
}

function text(value, maxLength) {
  return String(value == null ? '' : value).trim().slice(0, maxLength);
}

function encodePayload(data) {
  const bytes = new TextEncoder().encode(JSON.stringify(data));
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return 'V1:' + btoa(binary)
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');
}

function validateApplication(input) {
  const data = {
    name: text(input && input.name, 30),
    team: Number(input && input.team),
    teamName: text(input && input.teamName, 40),
    qq: text(input && input.qq, 15),
    image: '',
    desc: text(input && input.desc, 40),
    bio: text(input && input.bio, 200),
    coachChoice: (input && input.coachChoice && (typeof input.coachChoice === 'object')) ? input.coachChoice : null,
    submittedAt: new Date().toISOString()
  };
  if (!data.name) throw new Error('请填写姓名。');
  if (!Number.isInteger(data.team) || data.team < 1 || data.team > 999) {
    throw new Error('所属团队无效。');
  }
  if (!data.teamName) throw new Error('所属团队名称无效。');
  if (data.qq && !/^\d+$/.test(data.qq)) throw new Error('QQ号只能是数字。');
  data.image = data.qq ? 'qq:' + data.qq : '';
  return data;
}

// 教官注册申请验证
function validateCoachRegister(input) {
  const data = {
    type: 'coach-register',
    username: text(input && input.username, 30),
    password: String((input && input.password) || ''),
    coachName: text(input && input.coachName, 30),
    team: Number(input && input.team),
    teamName: text(input && input.teamName, 40),
    bio: text(input && input.bio, 200),
    submittedAt: new Date().toISOString()
  };
  if (!data.username) throw new Error('请填写用户名。');
  if (!/^[A-Za-z0-9_\u4e00-\u9fa5]{2,30}$/.test(data.username)) throw new Error('用户名只能用中文、字母、数字、下划线，2-30 个字符。');
  if (!data.password || data.password.length < 4) throw new Error('密码至少 4 位。');
  if (data.password.length > 60) throw new Error('密码过长。');
  if (!data.coachName) throw new Error('请填写教官名。');
  if (!Number.isInteger(data.team) || data.team < 1) throw new Error('所属团队无效。');
  if (!data.teamName) throw new Error('所属团队名称无效。');
  return data;
}

async function createIssue(data, env) {
  const repository = String(env.GITHUB_REPOSITORY || DEFAULT_REPOSITORY);
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository)) {
    throw new Error('GITHUB_REPOSITORY 配置无效。');
  }
  const code = encodePayload(data);
  const isCoach = data.type === 'coach-register';
  const label = isCoach ? COACH_LABEL : String(env.JOIN_ISSUE_LABEL || DEFAULT_LABEL);
  const title = isCoach
    ? '教官注册申请：' + data.username + ' → ' + data.coachName
    : '入队申请：' + data.name + ' → ' + data.teamName;
  const body = isCoach ? [
    '**用户名**: ' + data.username,
    '**教官名**: ' + data.coachName,
    '**团队**: ' + data.teamName + ' (id=' + data.team + ')',
    '**简介**: ' + (data.bio || '(未填)'),
    '',
    '<!-- coach-register-base64 -->',
    code,
    '<!-- /coach-register-base64 -->'
  ].join('\n') : [
    '**姓名**: ' + data.name,
    '**团队**: ' + data.teamName + ' (id=' + data.team + ')',
    '**QQ**: ' + (data.qq || '(未填)'),
    '**身份/警号**: ' + (data.desc || '(未填)'),
    '**简介**: ' + (data.bio || '(未填)'),
    data.coachChoice ? '**选择教官**: ' + (data.coachChoice.name || '') : '',
    '',
    '<!-- join-payload-base64 -->',
    code,
    '<!-- /join-payload-base64 -->'
  ].filter(Boolean).join('\n');
  const apiUrl = 'https://api.github.com/repos/' + repository + '/issues';
  const headers = {
    'Accept': 'application/vnd.github+json',
    'Authorization': 'Bearer ' + env.GITHUB_PAT,
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': '9178gg-join-worker',
    'Content-Type': 'application/json'
  };
  const issue = {
    title,
    body,
    labels: [label]
  };
  let response = await fetch(apiUrl, {
    method: 'POST',
    headers,
    body: JSON.stringify(issue)
  });
  if (response.status === 422) {
    delete issue.labels;
    response = await fetch(apiUrl, {
      method: 'POST',
      headers,
      body: JSON.stringify(issue)
    });
  }
  const result = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(result.message || 'GitHub Issue 创建失败。');
    error.status = response.status;
    throw error;
  }
  return result;
}

export default {
  async fetch(request, env) {
    const origin = allowedOrigin(request.headers.get('Origin') || '', env);
    if (request.method === 'OPTIONS') {
      if (!origin) return json({ error: '不允许的网站来源。' }, 403, '');
      return new Response(null, {
        status: 204,
        headers: {
          'Access-Control-Allow-Origin': origin,
          'Access-Control-Allow-Methods': 'POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
          'Access-Control-Max-Age': '86400',
          'Vary': 'Origin'
        }
      });
    }
    if (request.method === 'GET') {
      // The admin page may be opened from file://, whose browser origin is "null".
      // This endpoint exposes health metadata only; POST remains origin-restricted.
      return json({ ok: true, service: '9178gg-join' }, 200, '*');
    }
    if (request.method !== 'POST') return json({ error: '只允许 POST。' }, 405, origin);
    if (!origin) return json({ error: '不允许的网站来源。' }, 403, '');
    if (!env.GITHUB_PAT) return json({ error: 'Worker 尚未配置 GITHUB_PAT Secret。' }, 503, origin);

    try {
      const input = await request.json();
      const isCoachReg = input && input.type === 'coach-register';
      const application = isCoachReg ? validateCoachRegister(input) : validateApplication(input);
      const issue = await createIssue(application, env);
      return json({
        ok: true,
        number: issue.number,
        html_url: issue.html_url
      }, 201, origin);
    } catch (error) {
      const status = Number(error && error.status) || 400;
      return json({ error: error && error.message || '提交失败。' }, status, origin);
    }
  }
};
