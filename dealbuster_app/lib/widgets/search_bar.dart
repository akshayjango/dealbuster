import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/svg_icons.dart';

const _kSuggestions = [
  'Shoes',
  'Headphones',
  'Face wash',
  'Smart watch',
  'Backpacks',
  'Air fryer',
];

/// A pill search field. In trigger mode (home screen) it's just a tappable
/// affordance with a rotating suggestion; in editable mode (search screen)
/// it's a live [TextField] driving [onChanged].
class DealSearchBar extends StatefulWidget {
  const DealSearchBar({
    super.key,
    this.editable = false,
    this.onTap,
    this.onChanged,
    this.controller,
    this.autofocus = false,
    this.onBack,
  });

  final bool editable;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final TextEditingController? controller;
  final bool autofocus;
  // When set, the leading search icon is swapped for a back chevron (the
  // search screen's use of this bar) instead of the plain magnifying glass
  // shown on the home screen's trigger version.
  final VoidCallback? onBack;

  @override
  State<DealSearchBar> createState() => _DealSearchBarState();
}

class _DealSearchBarState extends State<DealSearchBar>
    with SingleTickerProviderStateMixin {
  int _wordIndex = 0;
  late final AnimationController _fade;

  @override
  void initState() {
    super.initState();
    _fade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    )..forward();
    if (!widget.editable) _scheduleNextWord();
  }

  void _scheduleNextWord() {
    Future.delayed(const Duration(seconds: 2, milliseconds: 200), () async {
      if (!mounted) return;
      await _fade.reverse();
      if (!mounted) return;
      setState(() => _wordIndex = (_wordIndex + 1) % _kSuggestions.length);
      await _fade.forward();
      _scheduleNextWord();
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final field = Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: cardShadow(),
      ),
      child: Row(
        children: [
          if (widget.onBack != null)
            GestureDetector(
              onTap: widget.onBack,
              behavior: HitTestBehavior.opaque,
              child: const Icon(
                Icons.chevron_left_rounded,
                size: 26,
                color: AppColors.ink,
              ),
            )
          else
            const SvgIcon(SvgIcons.search, size: 19, color: AppColors.ink400),
          const SizedBox(width: 10),
          Expanded(
            child: widget.editable
                ? TextField(
                    controller: widget.controller,
                    autofocus: widget.autofocus,
                    onChanged: widget.onChanged,
                    style: Theme.of(context).textTheme.bodyLarge,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: 'Search deals',
                    ),
                  )
                : Row(
                    children: [
                      Text(
                        'Search for  ',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      FadeTransition(
                        opacity: _fade,
                        child: Text(
                          '"${_kSuggestions[_wordIndex]}"',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
          ),
          if (widget.editable &&
              widget.controller != null &&
              widget.controller!.text.isNotEmpty) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                widget.controller!.clear();
                widget.onChanged?.call('');
              },
              behavior: HitTestBehavior.opaque,
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: AppColors.hairline,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close_rounded,
                  size: 14,
                  color: AppColors.ink700,
                ),
              ),
            ),
          ],
        ],
      ),
    );

    if (widget.editable) return field;
    return GestureDetector(onTap: widget.onTap, child: field);
  }
}
