const DEFAULT_REPOSITORY = 'Xjrxjr/9178gg';
const DEFAULT_ORIGIN = 'https://xjrxjr.github.io';
const DEFAULT_LABEL = 'join-application';

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

function repositoryName(env) {
  const repository = String(env.GITHUB_REPOSITORY || DEFAULT_REPOSITORY);
  if (!/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(repository)) {
    throw new Error('GITHUB_REPOSITORY 配置无效。');
  }
  return repository;
}

function githubHeaders(env) {
  return {
    'Accept': 'application/vnd.github+json',
    'Authorization': 'Bearer ' + env.GITHUB_PAT,
    'X-GitHub-Api-Version': '2022-11-28',
    'User-Agent': '9178gg-join-worker',
    'Content-Type': 'application/json'
  };
}

async function sha256(value) {
  const bytes = new TextEncoder().encode(String(value));
  const digest = await crypto.subtle.digest('SHA-256', bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, '0'))
    .join('');
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

async function createIssue(data, trackingHash, env) {
  const repository = repositoryName(env);
  const code = encodePayload(data);
  const body = [
    '**姓名**: ' + data.name,
    '**团队**: ' + data.teamName + ' (id=' + data.team + ')',
    '**QQ**: ' + (data.qq || '(未填)'),
    '**身份/警号**: ' + (data.desc || '(未填)'),
    '**简介**: ' + (data.bio || '(未填)'),
    '',
    '<!-- join-payload-base64 -->',
    code,
    '<!-- /join-payload-base64 -->',
    '<!-- join-tracking-sha256:' + trackingHash + ' -->'
  ].join('\n');
  const apiUrl = 'https://api.github.com/repos/' + repository + '/issues';
  const headers = githubHeaders(env);
  const issue = {
    title: '入队申请：' + data.name + ' → ' + data.teamName,
    body,
    labels: [String(env.JOIN_ISSUE_LABEL || DEFAULT_LABEL)]
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

async function applicationStatus(request, env) {
  const url = new URL(request.url);
  const issueNumber = Number(url.searchParams.get('issue'));
  const trackingId = String(url.searchParams.get('tracking') || '').trim();
  if (!Number.isInteger(issueNumber) || issueNumber < 1 || !/^[a-f0-9]{32}$/i.test(trackingId)) {
    const error = new Error('申请查询参数无效。');
    error.status = 400;
    throw error;
  }

  const repository = repositoryName(env);
  const apiUrl = 'https://api.github.com/repos/' + repository + '/issues/' + issueNumber;
  const response = await fetch(apiUrl, { headers: githubHeaders(env) });
  const issue = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(response.status === 404 ? '找不到该申请。' : (issue.message || '查询申请失败。'));
    error.status = response.status;
    throw error;
  }
  const body = String(issue.body || '');
  const trackingHash = await sha256(trackingId);
  const validTracking =
    body.includes('<!-- join-tracking-sha256:' + trackingHash + ' -->') ||
    body.includes('<!-- join-tracking:' + trackingId + ' -->');
  if (!validTracking) {
    const error = new Error('找不到该申请。');
    error.status = 404;
    throw error;
  }
  if (issue.state === 'open') {
    return { ok: true, number: issueNumber, status: 'pending', updated_at: issue.updated_at };
  }

  const commentsResponse = await fetch(apiUrl + '/comments?per_page=100', {
    headers: githubHeaders(env)
  });
  const comments = await commentsResponse.json().catch(() => []);
  if (!commentsResponse.ok) {
    const error = new Error(comments && comments.message || '查询审批结果失败。');
    error.status = commentsResponse.status;
    throw error;
  }
  const bodies = (Array.isArray(comments) ? comments : [])
    .map((comment) => String(comment && comment.body || ''))
    .reverse();
  const approvedComment = bodies.find((body) =>
    body.includes('<!-- join-result:approved -->') || body.includes('申请已通过')
  );
  const rejectedComment = bodies.find((body) =>
    body.includes('<!-- join-result:rejected -->') || body.includes('申请未通过') || body.includes('未通过')
  );
  let status = 'closed';
  let personId = '';
  if (approvedComment) {
    status = 'approved';
    const match = approvedComment.match(/<!--\s*join-person-id:([A-Za-z0-9_-]+)\s*-->/);
    personId = match ? match[1] : '';
  } else if (rejectedComment) {
    status = 'rejected';
  }
  return {
    ok: true,
    number: issueNumber,
    status,
    person_id: personId,
    updated_at: issue.updated_at
  };
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
          'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
          'Access-Control-Allow-Headers': 'Content-Type',
          'Access-Control-Max-Age': '86400',
          'Vary': 'Origin'
        }
      });
    }
    if (request.method === 'GET') {
      const url = new URL(request.url);
      if (url.pathname.replace(/\/+$/, '') === '/status') {
        if (!origin) return json({ error: '不允许的网站来源。' }, 403, '');
        if (!env.GITHUB_PAT) return json({ error: 'Worker 尚未配置 GITHUB_PAT Secret。' }, 503, origin);
        try {
          return json(await applicationStatus(request, env), 200, origin);
        } catch (error) {
          const status = Number(error && error.status) || 400;
          return json({ error: error && error.message || '查询失败。' }, status, origin);
        }
      }
      // 健康检查不包含敏感数据，允许本地 admin.html 读取。
      return json({ ok: true, service: '9178gg-join' }, 200, '*');
    }
    if (request.method !== 'POST') return json({ error: '只允许 POST。' }, 405, origin);
    if (!origin) return json({ error: '不允许的网站来源。' }, 403, '');
    if (!env.GITHUB_PAT) return json({ error: 'Worker 尚未配置 GITHUB_PAT Secret。' }, 503, origin);

    try {
      const input = await request.json();
      const application = validateApplication(input);
      const trackingId = crypto.randomUUID().replace(/-/g, '');
      const issue = await createIssue(application, await sha256(trackingId), env);
      return json({
        ok: true,
        number: issue.number,
        html_url: issue.html_url,
        tracking_id: trackingId
      }, 201, origin);
    } catch (error) {
      const status = Number(error && error.status) || 400;
      return json({ error: error && error.message || '提交失败。' }, status, origin);
    }
  }
};
