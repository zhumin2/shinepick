import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/auth/login_page.dart';
import '../../features/home/home_page.dart';

/// 应用路由：未登录 → 登录页；已登录 → 首页。
class AppRouter {
  /// [auth] 接入 refreshListenable：登录态变化时重新执行 redirect。
  static GoRouter createRouter(AuthController auth) {
    return GoRouter(
      initialLocation: '/login',
      refreshListenable: auth,
      redirect: (context, state) {
        final auth = context.read<AuthController>();
        final loggingIn = state.matchedLocation == '/login';
        if (auth.status == AuthStatus.authenticated) {
          return loggingIn ? '/home' : null;
        }
        if (auth.status == AuthStatus.unauthenticated) {
          return loggingIn ? null : '/login';
        }
        // unknown：正在恢复登录态，先停在登录页
        return null;
      },
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginPage(),
        ),
        GoRoute(
          path: '/home',
          builder: (context, state) => const HomePage(),
        ),
      ],
    );
  }
}
