import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';

import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/checkin/checkin_controller.dart';
import 'features/garden/garden_controller.dart';
import 'features/social/social_controller.dart';
import 'shared/storage/token_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();

  final tokenStore = TokenStore();
  await tokenStore.init();
  final authController = AuthController(tokenStore);
  await authController.restore();
  final checkinController = CheckinController(authController);
  final socialController = SocialController(authController);
  final gardenController = GardenController(authController);

  runApp(ShinePickApp(
    authController: authController,
    checkinController: checkinController,
    socialController: socialController,
    gardenController: gardenController,
  ));
}

class ShinePickApp extends StatelessWidget {
  final AuthController authController;
  final CheckinController checkinController;
  final SocialController socialController;
  final GardenController gardenController;
  const ShinePickApp({
    super.key,
    required this.authController,
    required this.checkinController,
    required this.socialController,
    required this.gardenController,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: authController),
        ChangeNotifierProvider.value(value: checkinController),
        ChangeNotifierProvider.value(value: socialController),
        ChangeNotifierProvider.value(value: gardenController),
      ],
      child: MaterialApp.router(
        title: '拾光 ShinePick',
        theme: AppTheme.light(),
        routerConfig: AppRouter.createRouter(authController),
      ),
    );
  }
}
