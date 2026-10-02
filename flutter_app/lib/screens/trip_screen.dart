import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../core/network/api_failure.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_spacing.dart';
import '../core/widgets/app_back_button.dart';
import '../data/repositories/travel_repository.dart';
import '../models/travel_models.dart';
import 'home_screen.dart';
import 'journey/trip_result_view.dart';

/// A saved plan opened from 我的行程.
///
/// It is the same presentation as the plan generated on the journey page, via
/// [TripResultView]. Keeping one renderer is what stops the two entrances from
/// drifting apart.
class TripScreen extends ConsumerStatefulWidget {
  const TripScreen({super.key, required this.plan});

  final TravelPlan plan;

  @override
  ConsumerState<TripScreen> createState() => _TripScreenState();
}

class _TripScreenState extends ConsumerState<TripScreen> {
  late TravelPlan _plan;
  Map<String, String> _images = const <String, String>{};

  @override
  void initState() {
    super.initState();
    _plan = widget.plan;
    unawaited(_loadCatalog());
  }

  Future<void> _loadCatalog() async {
    try {
      final CatalogResult catalog =
          await ref.read(travelRepositoryProvider).fetchDestinations();
      if (!mounted) {
        return;
      }
      setState(() {
        _images = <String, String>{
          for (final Destination destination in catalog.destinations)
            if (destination.image.isNotEmpty) destination.name: destination.image,
        };
      });
    } on ApiFailure {
      // Photographs are optional here; the plan renders without them.
    }
  }

  @override
  Widget build(BuildContext context) {
    final double page = AppSpacing.pageFor(MediaQuery.sizeOf(context).width);
    return Scaffold(
      backgroundColor: AppColors.ground,
      appBar: AppBar(
        // 显式返回按钮，不依赖 AppBar 的自动 leading。这一页是 push 出来的，
        // 但因为它是全屏深读页（底部导航被盖住），返回按钮一旦被系统"省掉"，
        // 用户就被困在这里。见 AppBackButton 的注释。
        leading: AppBackButton(
          fallback: (BuildContext context) => const HomeScreen(),
        ),
        title: Text(
          _plan.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: RefreshIndicator(
        color: AppColors.celadon,
        onRefresh: _loadCatalog,
        child: ListView(
          padding: EdgeInsets.fromLTRB(page, 4, page, 40),
          children: <Widget>[
            TripResultView(
              plan: _plan,
              images: _images,
              onPlanChanged: (TravelPlan next) => setState(() => _plan = next),
            ),
          ],
        ),
      ),
    );
  }
}
