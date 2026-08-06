import 'dart:async';
import 'package:flutter/material.dart';

class CustomSearchBar extends StatefulWidget {
  final ValueChanged<String> onSearch;
  final VoidCallback onClear;
  final TextEditingController controller;

  const CustomSearchBar({
    super.key,
    required this.onSearch,
    required this.onClear,
    required this.controller,
  });

  @override
  State<CustomSearchBar> createState() => _CustomSearchBarState();
}

class _CustomSearchBarState extends State<CustomSearchBar> {
  static const List<String> _placeholderWords = [
    'Shoes',
    'Shampoo',
    'Watch',
    'Deodorant',
    'Body Lotion',
  ];

  int _currentIndex = 0;
  Timer? _placeholderTimer;
  bool _showPlaceholder = true;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _startPlaceholderRotation();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _placeholderTimer?.cancel();
    widget.controller.removeListener(_onTextChanged);
    _focusNode.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    setState(() {
      _showPlaceholder = widget.controller.text.isEmpty;
    });
  }

  void _startPlaceholderRotation() {
    _placeholderTimer = Timer.periodic(const Duration(milliseconds: 2200), (timer) {
      if (!mounted) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _placeholderWords.length;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFFE7E8F0),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF17192B).withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: const Color(0xFF17192B).withValues(alpha: 0.04),
            blurRadius: 24,
            offset: const Offset(0, 8),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.centerLeft,
        children: [
          // ── Text Input ──
          TextField(
            controller: widget.controller,
            focusNode: _focusNode,
            onSubmitted: widget.onSearch,
            style: const TextStyle(
              fontFamily: 'Plus Jakarta Sans',
              fontWeight: FontWeight.w500,
              fontSize: 14,
              color: Color(0xFF1A1D2E),
            ),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.only(left: 16, right: 80, bottom: 4),
              border: InputBorder.none,
              isDense: true,
              suffixIcon: widget.controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.close,
                        size: 18,
                        color: Color(0xFF6E7385),
                      ),
                      onPressed: () {
                        widget.controller.clear();
                        widget.onClear();
                      },
                    )
                  : null,
            ),
          ),

          // ── Rotating Placeholder Animation ──
          if (_showPlaceholder)
            IgnorePointer(
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Row(
                  children: [
                    const Text(
                      'Search for ',
                      style: TextStyle(
                        fontFamily: 'Plus Jakarta Sans',
                        fontWeight: FontWeight.w400,
                        fontSize: 14,
                        color: Color(0xFF6E7385),
                      ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 350),
                        transitionBuilder: (child, animation) {
                          return SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, 0.8),
                              end: Offset.zero,
                            ).animate(CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutCubic,
                            )),
                            child: FadeTransition(
                              opacity: animation,
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          '"${_placeholderWords[_currentIndex]}"',
                          key: ValueKey<int>(_currentIndex),
                          style: const TextStyle(
                            fontFamily: 'Plus Jakarta Sans',
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                            color: Color(0xFF6E7385),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Action Icon Button (Right aligned) ──
          Positioned(
            right: 4,
            child: SizedBox(
              width: 40,
              height: 40,
              child: IconButton(
                padding: EdgeInsets.zero,
                icon: const Icon(
                  Icons.search,
                  size: 22,
                  color: Color(0xFF1A1D2E),
                ),
                onPressed: () {
                  widget.onSearch(widget.controller.text);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
