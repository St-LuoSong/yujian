import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A photograph with a predictable box, a soft placeholder and a themed
/// fallback.
///
/// The discover page and the day cards are image led, so the image must never
/// be the reason the layout jumps: the height is always fixed by the caller,
/// the placeholder uses the brand tint instead of a grey box, and a failed
/// load still produces something that belongs to the product rather than a
/// broken-image glyph.
///
/// Photos are read through the disk cache, so an attraction already seen stays
/// visible on a weak connection or offline instead of degrading to a
/// placeholder. `url` is expected to be resolved already: see
/// `AppConfig.resolveMediaUrl` for why a photo uploaded in the operator
/// console arrives as `localhost` and must be re-pointed before it reaches a
/// phone.
class PhotoPlate extends StatelessWidget {
  const PhotoPlate({
    super.key,
    required this.url,
    required this.height,
    this.width,
    this.radius = 0,
    this.scrim = false,
    this.fit = BoxFit.cover,
    this.fallbackLabel,
    this.semanticLabel,
  });

  final String url;
  final double height;
  final double? width;
  final double radius;

  /// Draws a dark gradient over the lower half so white text stays readable.
  final bool scrim;

  final BoxFit fit;

  /// Short caption shown on the fallback, for example the attraction name.
  final String? fallbackLabel;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final Widget image = url.isEmpty
        ? _Fallback(label: fallbackLabel)
        : Semantics(
            image: true,
            label: semanticLabel,
            child: CachedNetworkImage(
              imageUrl: url,
              height: height,
              width: width,
              fit: fit,
              // 占位块先淡入、图片再交叉淡入：弱网下是"由虚到实"，
              // 而不是"空一块 → 突然出现一张图"。
              fadeInDuration: const Duration(milliseconds: 260),
              fadeOutDuration: const Duration(milliseconds: 120),
              placeholderFadeInDuration: const Duration(milliseconds: 180),
              // Real progress when the server reports byte counts, so a slow
              // connection shows movement instead of a static block.
              progressIndicatorBuilder: (_, __, DownloadProgress progress) =>
                  _Placeholder(
                height: height,
                width: width,
                progress: progress.progress,
              ),
              errorWidget: (_, __, ___) => _Fallback(label: fallbackLabel),
            ),
          );

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        height: height,
        width: width,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            image,
            if (scrim)
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      Color(0x00121C1A),
                      Color(0x73121C1A),
                      Color(0xD9121C1A),
                    ],
                    stops: <double>[0.30, 0.62, 1],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.height, this.width, this.progress});

  final double height;
  final double? width;

  /// Fraction of the photograph that has arrived, or null when the server did
  /// not report a length.
  ///
  /// The ring is drawn only when the value is known. An indeterminate spinner
  /// never stops scheduling frames, so it would both hang the layout suite on
  /// `pumpAndSettle` and show motion that carries no information; with an
  /// unknown length the gradient alone is the placeholder.
  final double? progress;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: width,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[AppColors.surfaceTint, AppColors.celadonPale],
          ),
        ),
        alignment: Alignment.center,
        child: progress == null
            ? null
            : SizedBox(
                width: 26,
                height: 26,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  value: progress,
                  color: AppColors.celadon,
                  backgroundColor: Colors.white24,
                ),
              ),
      );
}

/// Themed stand-in: 河南 as a ridge line under a celadon sky, not a broken
/// image icon.
class _Fallback extends StatelessWidget {
  const _Fallback({this.label});

  final String? label;

  @override
  Widget build(BuildContext context) => Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              AppColors.celadonPale,
              AppColors.surfaceTint,
              AppColors.sandSurface,
            ],
          ),
        ),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.landscape_outlined,
              color: AppColors.celadon,
              size: 30,
            ),
            if (label != null && label!.isNotEmpty) ...<Widget>[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  label!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.celadonDeep,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
}
