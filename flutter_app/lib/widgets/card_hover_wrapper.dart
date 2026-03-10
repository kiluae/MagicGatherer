import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../theme/dark_theme.dart';

/// Wraps a child widget to show a high-res card image preview on hover (desktop)
/// or long-press (mobile). Uses [Overlay] for z-order so the image floats above
/// everything.
class CardHoverWrapper extends StatefulWidget {
  final Widget child;
  final String imageUrl;

  const CardHoverWrapper({
    super.key,
    required this.child,
    required this.imageUrl,
  });

  @override
  State<CardHoverWrapper> createState() => _CardHoverWrapperState();
}

class _CardHoverWrapperState extends State<CardHoverWrapper> {
  OverlayEntry? _overlayEntry;

  static const double _w = 240;
  static const double _h = 336;
  static const double _cursorOffset = 16;

  void _showOverlay(Offset globalPosition) {
    _hideOverlay();
    if (widget.imageUrl.isEmpty) return;

    _overlayEntry = OverlayEntry(builder: (ctx) {
      final screen = MediaQuery.sizeOf(ctx);

      double left = globalPosition.dx + _cursorOffset;
      double top  = globalPosition.dy - _h / 2;

      // Keep inside screen bounds
      if (left + _w > screen.width)  left = globalPosition.dx - _w - _cursorOffset;
      if (top + _h > screen.height)  top  = screen.height - _h - 8;
      if (top < 0) top = 8;
      left = left.clamp(0.0, screen.width - _w);

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
                  imageUrl: widget.imageUrl,
                  fit: BoxFit.fill,
                  placeholder: (_, __) => Container(
                    color: kBgCard,
                    child: const Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                  errorWidget: (_, __, ___) => Container(
                    color: kBgCard,
                    child: const Icon(Icons.image_not_supported,
                        color: kTextMuted),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  void dispose() {
    _hideOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (event) => _showOverlay(event.position),
      onHover: (event) {
        _hideOverlay();
        _showOverlay(event.position);
      },
      onExit: (_) => _hideOverlay(),
      child: GestureDetector(
        onLongPressStart: (details) => _showOverlay(details.globalPosition),
        onLongPressEnd: (_) => _hideOverlay(),
        child: widget.child,
      ),
    );
  }
}
