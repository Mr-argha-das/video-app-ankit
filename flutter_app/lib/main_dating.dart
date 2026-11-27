import 'package:flutter/material.dart';
import 'config/app_flavor.dart';
import 'main.dart' as app;

void main() {
  AppFlavorConfig.current = AppFlavor.dating;
  app.main();
}
