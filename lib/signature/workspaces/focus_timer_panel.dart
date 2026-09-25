import 'dart:async';
import 'package:flutter/material.dart';
import '../../presentation/design_system/wingman_tokens.dart';
import 'workspace_controller.dart';

class FocusTimerPanel extends StatefulWidget {
  const FocusTimerPanel({
    super.key,
    required this.controller,
    required this.task,
    required this.busy,
    required this.run,
    required this.onCustom,
  });
  final WorkspaceController controller;
  final FinishWorkspace task;
  final bool busy;
  final Future<void> Function(Future<void> Function()) run;
  final VoidCallback onCustom;
  @override
  State<FocusTimerPanel> createState() => _FocusTimerPanelState();
}

class _FocusTimerPanelState extends State<FocusTimerPanel> {
  Timer? _ticker;
  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      // Repaints only. Countdown truth is a monotonic duration in the controller,
      // so missed frames and wall-clock changes cause no drift.
      if (mounted && widget.task.timer?.running == true) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final timer = widget.task.timer;
    final remaining = widget.controller.timerRemainingSeconds(widget.task.id);
    final text =
        '${remaining ~/ 60}:${(remaining % 60).toString().padLeft(2, '0')}';
    final tokens = WingmanTokens.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (timer == null) ...[
          Icon(Icons.timelapse, size: 64, color: tokens.action),
          const SizedBox(height: 16),
          Text(
            'A little time for one thing',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 12),
          const Text(
            'Add an optional focus timer. Your task works without one.',
            textAlign: TextAlign.center,
          ),
        ] else ...[
          LayoutBuilder(
            builder: (context, constraints) {
              final diameter = constraints.maxWidth.clamp(120.0, 260.0);
              final largeText = MediaQuery.textScalerOf(context).scale(16) > 24;
              final caption = remaining == 0
                  ? 'Time is up. Finish when you are ready.'
                  : '${timer.running ? 'left' : 'paused'} in your ${timer.durationSeconds ~/ 60}-minute session';
              return Column(
                children: [
                  SizedBox(
                    width: diameter,
                    height: diameter,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        SizedBox.expand(
                          child: CircularProgressIndicator(
                            value: remaining / timer.durationSeconds,
                            strokeWidth: 7,
                            backgroundColor: tokens.divider,
                            color: WingmanTokens.cyan,
                            semanticsLabel: 'Focus timer, $text remaining',
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                child: Text(
                                  text,
                                  style: Theme.of(context)
                                      .textTheme
                                      .displayLarge
                                      ?.copyWith(fontSize: 60),
                                ),
                              ),
                              if (!largeText) ...[
                                const SizedBox(height: 12),
                                Text(
                                  caption,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (largeText) ...[
                    const SizedBox(height: 16),
                    Text(
                      caption,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              OutlinedButton.icon(
                onPressed:
                    widget.busy ||
                        widget.task.status != FinishStatus.active ||
                        remaining == 0
                    ? null
                    : () => widget.run(
                        () => widget.controller.setTimerRunning(
                          widget.task.id,
                          !timer.running,
                        ),
                      ),
                icon: Icon(timer.running ? Icons.pause : Icons.play_arrow),
                label: Text(timer.running ? 'Pause timer' : 'Start timer'),
              ),
              TextButton(
                onPressed: widget.busy
                    ? null
                    : () => widget.run(
                        () => widget.controller.resetTimer(widget.task.id),
                      ),
                child: const Text('Reset timer'),
              ),
              TextButton(
                onPressed: widget.busy
                    ? null
                    : () => widget.run(
                        () => widget.controller.removeTimer(widget.task.id),
                      ),
                child: const Text('Remove timer'),
              ),
            ],
          ),
        ],
        if (widget.task.status != FinishStatus.finished) ...[
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              for (final minutes in [15, 25, 45])
                ActionChip(
                  label: Text('$minutes min'),
                  onPressed: widget.busy
                      ? null
                      : () => widget.run(
                          () => widget.controller.configureTimer(
                            widget.task.id,
                            minutes: minutes,
                          ),
                        ),
                ),
              ActionChip(
                label: const Text('Custom'),
                onPressed: widget.busy ? null : widget.onCustom,
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Text(
          'Your timer pauses when Wingman leaves the foreground. After a restart, it is paused at its last saved checkpoint.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
