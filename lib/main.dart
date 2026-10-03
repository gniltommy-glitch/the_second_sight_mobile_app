import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_state.dart';
import 'ui/home.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Force portrait on Android.
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Full edge-to-edge display.
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      systemNavigationBarColor: Color(0xFF0B1017),
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const SecondSightApp());
}

// ─── Design tokens (premium dark — reactbits-inspired) ──────────
const kBg      = Color(0xFF0D1117);  // GitHub-dark depth
const kSurface = Color(0xFF161B22);  // Card surface
const kCard2   = Color(0xFF1C2430);  // Secondary card
const kAccent  = Color(0xFF22D3A5);  // Vivid teal — primary CTA
const kAccent2 = Color(0xFF818CF8);  // Indigo — secondary
const kDanger  = Color(0xFFFF5370);  // Coral red
const kWarning = Color(0xFFF59E0B);  // Amber
const kText    = Color(0xFFE6EDF3);  // Near-white
const kTextSub = Color(0xFF8B949E);  // Muted gray
const kBorder  = Color(0xFF21262D);  // Subtle border


class SecondSightApp extends StatefulWidget {
  const SecondSightApp({super.key});
  @override
  State<SecondSightApp> createState() => _SecondSightAppState();
}

class _SecondSightAppState extends State<SecondSightApp> {
  final state = AppState();

  @override
  void initState() {
    super.initState();
    state.init().catchError((Object e) => state.startupFailed(e));
  }

  @override
  void dispose() {
    state.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const base = TextStyle(fontFamily: 'BeVietnamPro');
    final textTheme = TextTheme(
      displayLarge: base.copyWith(
        fontSize: 57,
        fontWeight: FontWeight.w800,
        color: kText,
      ),
      displayMedium: base.copyWith(
        fontSize: 45,
        fontWeight: FontWeight.w700,
        color: kText,
      ),
      headlineLarge: base.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w800,
        color: kText,
        letterSpacing: -0.5,
      ),
      headlineMedium: base.copyWith(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: kText,
      ),
      titleLarge: base.copyWith(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: kText,
      ),
      titleMedium: base.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: kText,
      ),
      bodyLarge: base.copyWith(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: kText,
        height: 1.5,
      ),
      bodyMedium: base.copyWith(fontSize: 14, color: kTextSub, height: 1.5),
      labelLarge: base.copyWith(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: kText,
        letterSpacing: 0.3,
      ),
    );

    return MaterialApp(
      title: 'SecondSight',
      debugShowCheckedModeBanner: false,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'BeVietnamPro',
        brightness: Brightness.dark,
        scaffoldBackgroundColor: kBg,
        colorScheme: const ColorScheme.dark(
          primary: kAccent,
          secondary: kAccent2,
          error: kDanger,
          surface: kSurface,
          onPrimary: Color(0xFF001A14),
          onSecondary: Colors.white,
          onSurface: kText,
          onError: Colors.white,
        ),
        textTheme: textTheme,
        iconTheme: const IconThemeData(color: kAccent, size: 22),
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          titleTextStyle: base.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: kText,
          ),
          iconTheme: const IconThemeData(color: kAccent),
          systemOverlayStyle: const SystemUiOverlayStyle(
            statusBarIconBrightness: Brightness.light,
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: Colors.transparent,
          indicatorColor: kAccent.withValues(alpha: 0.18),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return const IconThemeData(color: kAccent, size: 22);
            }
            return const IconThemeData(color: kTextSub, size: 22);
          }),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return base.copyWith(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
              color: selected ? kAccent : kTextSub,
            );
          }),
          overlayColor: WidgetStateProperty.all(Colors.transparent),
          elevation: 0,
          height: 70,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: kSurface,
          hintStyle: base.copyWith(color: kTextSub),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: kAccent, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: kAccent,
            foregroundColor: const Color(0xFF001A14),
            textStyle: base.copyWith(fontSize: 14, fontWeight: FontWeight.w700),
            minimumSize: const Size(48, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            elevation: 0,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: kAccent,
            side: const BorderSide(color: kAccent, width: 1),
            textStyle: base.copyWith(fontSize: 14, fontWeight: FontWeight.w600),
            minimumSize: const Size(48, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: kAccent,
            textStyle: base.copyWith(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: kSurface,
          selectedColor: kAccent.withValues(alpha: 0.2),
          labelStyle: base.copyWith(fontSize: 12, color: kText),
          side: const BorderSide(color: kBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        cardTheme: CardThemeData(
          color: kSurface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: kBorder),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: kBorder,
          thickness: 1,
          space: 24,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: kAccent,
          inactiveTrackColor: kBorder,
          thumbColor: kAccent,
          overlayColor: kAccent.withValues(alpha: 0.12),
        ),
        switchTheme: SwitchThemeData(
          thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? kAccent
                : const Color(0xFF4B5563),
          ),
          trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
                ? kAccent.withValues(alpha: 0.35)
                : kBorder,
          ),
        ),
        dropdownMenuTheme: DropdownMenuThemeData(
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: kSurface,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: kBorder),
            ),
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          backgroundColor: kSurface,
          contentTextStyle: base.copyWith(color: kText),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          behavior: SnackBarBehavior.floating,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: kSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titleTextStyle: base.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: kText,
          ),
          contentTextStyle: base.copyWith(color: kTextSub, height: 1.5),
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          backgroundColor: kSurface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          ),
        ),
      ),
      home: ListenableBuilder(
        listenable: state,
        builder: (context, _) =>
            state.loaded ? Home(state: state) : const _SplashScreen(),
      ),
    );
  }
}

class _SplashScreen extends StatefulWidget {
  const _SplashScreen();
  @override
  State<_SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<_SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulse = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Center(
        child: AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) => Opacity(
            opacity: _pulse.value,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: kAccent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: kAccent.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.visibility_outlined,
                    color: kAccent,
                    size: 42,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'SecondSight',
                  style: TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: kAccent,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Đang khởi động...',
                  style: TextStyle(
                    fontFamily: 'BeVietnamPro',
                    fontSize: 13,
                    color: kTextSub,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
