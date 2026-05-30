import 'package:app/routing/adaptive.dart';
import 'package:app/ui/app_theme.dart';
import 'package:app/ui/onboarding/states/onboarding_state.dart';
import 'package:app/ui/onboarding/viewmodels/onboarding_viewmodel.dart';
import 'package:app/ui/onboarding/widgets/widgets.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _syncPage(OnboardingStep step) {
    final target = step.index.toDouble();
    if (!_pageController.hasClients) return;
    final current = _pageController.page ?? 0;
    if ((current - target).abs() < 0.01) return;
    _pageController.animateToPage(
      step.index,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<OnboardingViewModel>();
    final state = vm.state;

    if (state is OnboardingComplete) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go('/home');
      });
      return const Scaffold(backgroundColor: kBg, body: SizedBox.shrink());
    }

    final s = state as OnboardingInProgress;
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPage(s.step));

    return Scaffold(
      backgroundColor: kBg,
      // Plan/tablet — cap + centre the stepper on wide screens so the
      // phone-oriented column doesn't stretch edge-to-edge on iPad.
      body: SafeArea(
        child: ResponsiveCenter(
          child: Column(
            children: [
              _StepIndicator(step: s.step),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    WelcomeStep(onNext: vm.next),
                    RelayStep(
                      state: s,
                      onChoice: vm.setRelayChoice,
                      onCustomUrl: vm.setCustomRelayUrl,
                      onBack: vm.back,
                      onNext: vm.next,
                    ),
                    PairStep(
                      onPaired: () {
                        // ignore: unawaited_futures
                        vm.completePairing();
                      },
                      onBack: vm.back,
                      onSkip: () {
                        // ignore: unawaited_futures
                        vm.skipPairing();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StepIndicator extends StatelessWidget {
  final OnboardingStep step;
  const _StepIndicator({required this.step});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        children: List.generate(OnboardingStep.values.length, (i) {
          final active = i <= step.index;
          return Expanded(
            child: Container(
              margin: EdgeInsets.only(
                left: i == 0 ? 0 : 4,
                right: i == OnboardingStep.values.length - 1 ? 0 : 4,
              ),
              height: 3,
              decoration: BoxDecoration(
                color: active ? kAccent : kBorder,
                borderRadius: const BorderRadius.all(Radius.circular(2)),
              ),
            ),
          );
        }),
      ),
    );
  }
}
