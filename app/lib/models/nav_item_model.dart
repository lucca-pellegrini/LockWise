import 'rive_model.dart';

class NavItemModel {
  final RiveModel rive;
  final String title;

  NavItemModel({required this.rive, required this.title});
}

List<NavItemModel> bottomNavItems = [
  NavItemModel(
    title: "Home",
    rive: RiveModel(
      src: "assets/RiverAssets.riv",
      artboard: "HOME",
      stateMachineName: "HOME_interactivity",
    ),
  ),

  NavItemModel(
    title: "Bell",
    rive: RiveModel(
      src: "assets/RiverAssets.riv",
      artboard: "BELL",
      stateMachineName: "BELL_Interactivity",
    ),
  ),

  NavItemModel(
    title: "Settings",
    rive: RiveModel(
      src: "assets/RiverAssets.riv",
      artboard: "SETTINGS",
      stateMachineName: "SETTINGS_Interactivity",
    ),
  ),

  NavItemModel(
    title: "Timer",
    rive: RiveModel(
      src: "assets/RiverAssets.riv",
      artboard: "TIMER",
      stateMachineName: "TIMER_Interactivity",
    ),
  ),
];

