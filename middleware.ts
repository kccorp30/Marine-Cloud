import { createServerClient } from '@supabase/ssr';
import { NextResponse, type NextRequest } from 'next/server';

export async function middleware(request: NextRequest) {
  const requestHeaders = new Headers(request.headers);
  requestHeaders.set("x-kcc-path", request.nextUrl.pathname);
  let response = NextResponse.next({ request: {headers:requestHeaders} });

  const supabase = createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL!, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!, {
    cookies: {
      getAll() {
        return request.cookies.getAll();
      },
      setAll(cookiesToSet: { name: string; value: string; options?: Record<string, unknown> }[]) {
        cookiesToSet.forEach(({ name, value }) => request.cookies.set(name, value));
        response = NextResponse.next({ request: {headers: new Headers([...requestHeaders, ["cookie", request.cookies.toString()]])} });
        cookiesToSet.forEach(({ name, value, options }) => response.cookies.set(name, value, options));
      },
    },
  });

  const {
    data: { user },
  } = await supabase.auth.getUser();

  const PUBLIC_ROUTES = ['/login', '/forgot-password', '/reset-password', '/accept-invite', '/auth/confirm'];
  const isAuthRoute = PUBLIC_ROUTES.some((route) => request.nextUrl.pathname.startsWith(route));
  const isPublicAsset = request.nextUrl.pathname.startsWith('/_next') || request.nextUrl.pathname.includes('.');

  if (!user && !isAuthRoute && !isPublicAsset) {
    const url = request.nextUrl.clone();
    url.pathname = '/login';
    // Preserva a dónde iba, así /login (o cualquier página protegida)
    // puede mandarlo de vuelta después de autenticarse en vez de
    // perder el destino original — importante en particular para
    // /accept-invite?token=... que necesita conservar el token.
    url.searchParams.set('next', request.nextUrl.pathname + request.nextUrl.search);
    return NextResponse.redirect(url);
  }

  if (user && request.nextUrl.pathname === '/login') {
    const url = request.nextUrl.clone();
    url.pathname = '/';
    return NextResponse.redirect(url);
  }

  return response;
}

export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico).*)'],
};
