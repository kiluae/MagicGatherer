import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/dark_theme.dart';

/// Floating card preview that tracks the mouse.
/// Appears instantly on [CardPreviewOverlay] being added to the widget tree.
class CardPreviewOverlay extends StatelessWidget {
  final String imageUrl;
  final Offset position;

  const CardPreviewOverlay({
    super.key,
    required this.imageUrl,
    required this.position,
  });

  static const double _w = 240.0;
  static const double _h = 336.0;
  static const double _offset = 16.0;

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    double left = position.dx + _offset;
    double top  = position.dy + _offset;

    // Keep inside screen bounds
    if (left + _w > screen.width)  left = position.dx - _w - _offset;
    if (top  + _h > screen.height) top  = position.dy - _h - _offset;
    left = left.clamp(0, screen.width  - _w);
    top  = top .clamp(0, screen.height - _h);

    return Positioned(
      left: left,
      top:  top,
      child: IgnorePointer(
        child: PhysicalModel(
          color: Colors.transparent,
          elevation: 24,
          borderRadius: BorderRadius.circular(12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: _w, height: _h,
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                fit: BoxFit.fill,
                placeholder: (_, __) => Container(
                  color: kBgCard,
                  child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: kBgCard,
                  child: const Icon(Icons.image_not_supported, color: kTextMuted),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
