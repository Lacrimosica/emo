import type { RequestHandler } from './$types';

const WORKER_BASE = 'https://emo-server.m-gdrzi77.workers.dev';

const proxy: RequestHandler = async ({ params, request, url }) => {
  const target = `${WORKER_BASE}/api/${params.path}${url.search}`;

  const init: RequestInit = {
    method: request.method,
    headers: request.headers,
    redirect: 'manual', // Don't follow redirects — pass them straight to the browser
  };

  if (request.method !== 'GET' && request.method !== 'HEAD') {
    init.body = request.body;
  }

  return fetch(target, init);
};

export const GET    = proxy;
export const POST   = proxy;
export const PATCH  = proxy;
export const DELETE = proxy;
export const PUT    = proxy;
