import { redirect } from '@sveltejs/kit';

export const ssr = false;

export const load = async ({ fetch, url }) => {
  // Don't protect the login page
  if (url.pathname === '/login') return {};
  
  try {
    const res = await fetch('/api/auth/me');
    if (!res.ok) {
      throw redirect(302, '/login');
    }
    
    const { user } = await res.json();
    return { user };
  } catch (error) {
    if (error && typeof error === 'object' && 'status' in error && error.status === 302) {
      throw error;
    }
    throw redirect(302, '/login');
  }
};
