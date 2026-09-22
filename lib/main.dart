import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/app_state.dart';
import 'ui/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SecondSightApp());
}
class SecondSightApp extends StatefulWidget {
  const SecondSightApp({super.key});
  @override
  State<SecondSightApp> createState() => _SecondSightAppState();
}
class _SecondSightAppState extends State<SecondSightApp> {
  final state = AppState();
  @override
  void initState() { super.initState(); state.init().catchError((Object e) {
    state.startupFailed(e);
  }); }
  @override
  void dispose() { state.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'SecondSight', debugShowCheckedModeBanner: false,
    locale: const Locale('vi'), supportedLocales: const [Locale('vi'), Locale('en')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: ThemeData(useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF175C45),
        primary: const Color(0xFF175C45), surface: const Color(0xFFF7F8F2)),
      scaffoldBackgroundColor: const Color(0xFFF7F8F2),
      inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16))),
      filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(
        minimumSize: const Size(48, 54), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))),
      textTheme: const TextTheme(headlineLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
        titleLarge: TextStyle(fontWeight: FontWeight.w700), bodyLarge: TextStyle(height: 1.45))),
    home: ListenableBuilder(listenable: state, builder: (context, _) => state.loaded
      ? Home(state: state) : const Scaffold(body: Center(child: CircularProgressIndicator()))),
  );
}
