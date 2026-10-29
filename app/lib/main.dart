import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'shared/storage/token_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  final tokenStore = TokenStore();
  await tokenStore.init();
  final authController = AuthController(tokenStore);
  await authController.restore();

  runApp(ShinePickApp(authController: authController));
}

class ShinePickApp extends StatelessWidget {
  final AuthController authController;
  const ShinePickApp({super.key, required this.authController});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: authController,
      child: MaterialApp.router(
        title: '拾光 ShinePick',
        theme: AppTheme.light(),
        routerConfig: AppRouter.createRouter(authController),
      ),
    );
  }
}
