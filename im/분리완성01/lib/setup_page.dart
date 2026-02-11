import 'package:flutter/material.dart';
import 'setup_mobile_view.dart';
import 'setup_tablet_view.dart';

class SetupPage extends StatelessWidget {
  const SetupPage({super.key});

  @override
  Widget build(BuildContext context) {
    bool isTablet = MediaQuery.of(context).size.width > 600;

    if (isTablet) {
      return const SetupTabletView();
    } else {
      return const SetupMobileView();
    }
  }
}
