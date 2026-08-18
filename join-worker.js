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

function decodePayload(value) {
  try {
    let encoded = String(value || '').trim();
    if (encoded.startsWith('V1:')) encoded = encoded.slice(3);
    encoded = encoded.replace(/-/g, '+').replace(/_/g, '/');
    while (encoded.length % 4) encoded += '=';
    const binary = atob(encoded);
    const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
    return JSON.parse(new TextDecoder().decode(bytes));
  } catch {
    return null;
  }
}

function applicationFromIssue(issue) {
  const body = String(issue && issue.body || '');
  const match = body.match(/<!-- join-payload-base64 -->\s*([\s\S]*?)\s*<!-- \/join-payload-base64 -->/);
  return match ? decodePayload(match[1]) : null;
}

function coachChoiceFromComments(comments) {
  const list = Array.isArray(comments) ? comments.slice().reverse() : [];
  for (const comment of list) {
    const body = String(comment && comment.body || '');
    const match = body.match(/<!--\s*join-coach-choice-base64:([A-Za-z0-9_-]+)\s*-->/);
    if (!match) continue;
    const choice = decodePayload(match[1]);
    if (choice && choice.name) return choice;
  }
  return null;
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

function validateLookup(issueNumber, trackingId) {
  if (!Number.isInteger(issueNumber) || issueNumber < 1 || !/^[a-f0-9]{32}$/i.test(trackingId)) {
    const error = new Error('申请查询参数无效。');
    error.status = 400;
    throw error;
  }
}

async function trackedIssue(issueNumber, trackingId, env) {
  validateLookup(issueNumber, trackingId);
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
  return { apiUrl, issue, repository };
}

async function issueComments(apiUrl, env) {
  const commentsResponse = await fetch(apiUrl + '/comments?per_page=100', {
    headers: githubHeaders(env)
  });
  const comments = await commentsResponse.json().catch(() => []);
  if (!commentsResponse.ok) {
    const error = new Error(comments && comments.message || '查询审批结果失败。');
    error.status = commentsResponse.status;
    throw error;
  }
  return Array.isArray(comments) ? comments : [];
}

function resultFromComments(issue, comments) {
  if (issue.state === 'open') {
    return { status: 'pending', personId: '' };
  }
  const bodies = comments
    .map((comment) => String(comment && comment.body || ''))
    .reverse();
  const approvedComment = bodies.find((body) =>
    body.includes('<!-- join-result:approved -->') || body.includes('申请已通过')
  );
  const rejectedComment = bodies.find((body) =>
    body.includes('<!-- join-result:rejected -->') || body.includes('申请未通过') || body.includes('未通过')
  );
  if (approvedComment) {
    const match = approvedComment.match(/<!--\s*join-person-id:([A-Za-z0-9_-]+)\s*-->/);
    return { status: 'approved', personId: match ? match[1] : '' };
  }
  if (rejectedComment) return { status: 'rejected', personId: '' };
  return { status: 'closed', personId: '' };
}

async function applicationStatus(request, env) {
  const url = new URL(request.url);
  const issueNumber = Number(url.searchParams.get('issue'));
  const trackingId = String(url.searchParams.get('tracking') || '').trim();
  const tracked = await trackedIssue(issueNumber, trackingId, env);
  const application = applicationFromIssue(tracked.issue) || {};

  if (tracked.issue.state === 'open') {
    return {
      ok: true,
      number: issueNumber,
      status: 'pending',
      team: Number(application.team) || null,
      team_name: String(application.teamName || ''),
      coach_choice: null,
      updated_at: tracked.issue.updated_at
    };
  }
  const comments = await issueComments(tracked.apiUrl, env);
  const result = resultFromComments(tracked.issue, comments);
  return {
    ok: true,
    number: issueNumber,
    status: result.status,
    person_id: result.personId,
    team: Number(application.team) || null,
    team_name: String(application.teamName || ''),
    coach_choice: coachChoiceFromComments(comments),
    updated_at: tracked.issue.updated_at
  };
}

async function repositoryTeams(repository, env) {
  const branch = String(env.GITHUB_BRANCH || 'main')
    .split('/')
    .map((part) => encodeURIComponent(part))
    .join('/');
  const apiUrl = 'https://raw.githubusercontent.com/' + repository + '/' + branch + '/teams.json';
  const response = await fetch(apiUrl, { headers: { 'Accept': 'application/json' } });
  if (!response.ok) {
    const error = new Error('读取教练列表失败。');
    error.status = response.status;
    throw error;
  }
  try {
    const teams = await response.json();
    if (Array.isArray(teams)) return teams;
  } catch {}

  const error = new Error('教练列表格式无效。');
  error.status = 502;
  throw error;
}

async function selectCoach(request, env) {
  const input = await request.json().catch(() => ({}));
  const issueNumber = Number(input.issue);
  const trackingId = String(input.tracking || '').trim();
  const coachIndex = Number(input.coach_index);
  const coachName = text(input.coach_name, 60);
  if (!Number.isInteger(coachIndex) || coachIndex < 0 || !coachName) {
    const error = new Error('请选择有效的教练。');
    error.status = 400;
    throw error;
  }

  const tracked = await trackedIssue(issueNumber, trackingId, env);
  const comments = await issueComments(tracked.apiUrl, env);
  const result = resultFromComments(tracked.issue, comments);
  if (result.status !== 'approved') {
    const error = new Error('申请通过后才能选择教练。');
    error.status = 409;
    throw error;
  }

  const application = applicationFromIssue(tracked.issue);
  const teamId = Number(application && application.team);
  if (!Number.isInteger(teamId)) {
    const error = new Error('申请中缺少所属团队。');
    error.status = 422;
    throw error;
  }

  const teams = await repositoryTeams(tracked.repository, env);
  const team = teams.find((item) => Number(item && item.id) === teamId);
  const coaches = team && Array.isArray(team.coaches) ? team.coaches : [];
  const coach = coaches[coachIndex];
  if (!coach || coach.enabled !== true || String(coach.name || '').trim() !== coachName) {
    const error = new Error('该教练已不可选，请刷新页面后重试。');
    error.status = 409;
    throw error;
  }

  const choice = {
    team: teamId,
    index: coachIndex,
    name: coachName,
    selected_at: new Date().toISOString()
  };
  const marker = encodePayload(choice).slice(3);
  const response = await fetch(tracked.apiUrl + '/comments', {
    method: 'POST',
    headers: githubHeaders(env),
    body: JSON.stringify({
      body: '🧑‍🏫 申请人已选择教练：' + coachName +
        '\n\n<!-- join-coach-choice-base64:' + marker + ' -->'
    })
  });
  const comment = await response.json().catch(() => ({}));
  if (!response.ok) {
    const error = new Error(comment.message || '保存教练选择失败。');
    error.status = response.status;
    throw error;
  }
  return { ok: true, coach_choice: choice, updated_at: comment.updated_at };
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
      const url = new URL(request.url);
      if (url.pathname.replace(/\/+$/, '') === '/coach') {
        return json(await selectCoach(request, env), 200, origin);
      }
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
