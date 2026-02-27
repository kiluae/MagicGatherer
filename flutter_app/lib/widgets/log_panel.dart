import 'package:flutter/material.dart';
import '../theme/dark_theme.dart';

/// Dual-pane scrollable log panel matching the Python app's exec/error log layout.
class LogPanel extends StatefulWidget {
  final List<String> execLog;
  final List<String> errLog;

  const LogPanel({super.key, required this.execLog, required this.errLog});

  @override
  State<LogPanel> createState() => _LogPanelState();
}

class _LogPanelState extends State<LogPanel> {
  final _execScroll = ScrollController();
  final _errScroll  = ScrollController();

  @override
  void didUpdateWidget(LogPanel old) {
    super.didUpdateWidget(old);
    // Auto-scroll exec log to bottom on new entries
    if (widget.execLog.length != old.execLog.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_execScroll.hasClients) {
          _execScroll.animateTo(_execScroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut);
        }
      });
    }
  }

  @override
  void dispose() {
    _execScroll.dispose();
    _errScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Execution log (green text, 2/3 width)
        Expanded(
          flex: 2,
          child: _pane(
            label: 'Execution Log',
            messages: widget.execLog,
            color: kSuccess,
            controller: _execScroll,
            emptyMsg: 'Execution log will appear here…',
          ),
        ),
        const SizedBox(width: 8),
        // Error log (red text, 1/3 width)
        Expanded(
          flex: 1,
          child: _pane(
            label: 'Errors / Skipped',
            messages: widget.errLog,
            color: kError,
            controller: _errScroll,
            emptyMsg: 'Skipped or non-legal cards appear here…',
          ),
        ),
      ],
    );
  }

  Widget _pane({
    required String label,
    required List<String> messages,
    required Color color,
    required ScrollController controller,
    required String emptyMsg,
  }) =>
    Container(
      decoration: BoxDecoration(
        color: Colors.black,
        border: Border.all(color: kBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: kBgCard,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
            ),
            child: Text(label,
                style: TextStyle(color: color, fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ),
          // Log body
          Expanded(
            child: ListView.builder(
              controller: controller,
              padding: const EdgeInsets.all(8),
              itemCount: messages.isEmpty ? 1 : messages.length,
              itemBuilder: (_, i) {
                final text = messages.isEmpty ? emptyMsg : messages[i];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(text,
                      style: TextStyle(
                        color: messages.isEmpty ? color.withOpacity(0.4) : color,
                        fontSize: 11,
                        fontFamily: 'monospace',
                      )),
                );
              },
            ),
          ),
        ],
      ),
    );
}
