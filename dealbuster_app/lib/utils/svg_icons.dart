import 'package:flutter/widgets.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// A small family of consistent, single-stroke line icons.
///
/// Every glyph shares the same 24x24 grid, ~1.8 stroke weight and round caps
/// so the category strip reads as one designed set rather than borrowed
/// illustrations. Icons are colorless (`currentColor`-style black strokes) —
/// callers tint them via [SvgIcon]'s `color`.
class SvgIcons {
  SvgIcons._();

  static const deals = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M13 2 4 14h6l-1 8 9-12h-6l1-8Z" stroke="#000" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round"/>
</svg>''';

  static const all = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<rect x="3.5" y="3.5" width="7" height="7" rx="2" stroke="#000" stroke-width="1.7"/>
<rect x="13.5" y="3.5" width="7" height="7" rx="2" stroke="#000" stroke-width="1.7"/>
<rect x="3.5" y="13.5" width="7" height="7" rx="2" stroke="#000" stroke-width="1.7"/>
<rect x="13.5" y="13.5" width="7" height="7" rx="2" stroke="#000" stroke-width="1.7"/>
</svg>''';

  static const beauty = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M10 2.5h4M11 2.5v4.2c0 .5-.2 1-.6 1.3L8.6 9.7A3 3 0 0 0 7.5 12v7A2.5 2.5 0 0 0 10 21.5h4A2.5 2.5 0 0 0 16.5 19v-7c0-.9-.4-1.7-1-2.3l-1.9-1.7a1.8 1.8 0 0 1-.6-1.3V2.5" stroke="#000" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round"/>
<path d="M8 15.5h8" stroke="#000" stroke-width="1.6" stroke-linecap="round"/>
</svg>''';

  static const fashion = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M12 6.2a1.8 1.8 0 1 1 1.9 2.9L20 13.4c.9.5.6 1.9-.4 1.9H4.4c-1 0-1.3-1.4-.4-1.9l6.1-4.3A1.8 1.8 0 0 1 12 6.2Z" stroke="#000" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round"/>
<path d="M4 18.5h16" stroke="#000" stroke-width="1.7" stroke-linecap="round"/>
</svg>''';

  static const health = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M12 20s-7.5-4.6-9.6-9.6C1.2 6.9 3.5 4 6.8 4c2 0 3.6 1.2 5.2 3 1.6-1.8 3.2-3 5.2-3 3.3 0 5.6 2.9 4.4 6.4C19.5 15.4 12 20 12 20Z" stroke="#000" stroke-width="1.6" stroke-linejoin="round"/>
<path d="M4.5 12h3l1.5-2.5 2 4L12.5 10l1.5 3h5" stroke="#000" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>
</svg>''';

  static const home = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M4 11.5 12 4l8 7.5" stroke="#000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
<path d="M6 10v8.5A1.5 1.5 0 0 0 7.5 20H10v-5.5a2 2 0 0 1 4 0V20h2.5a1.5 1.5 0 0 0 1.5-1.5V10" stroke="#000" stroke-width="1.7" stroke-linejoin="round" stroke-linecap="round"/>
</svg>''';

  static const electronics = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M4 13.5v-1a8 8 0 1 1 16 0v1" stroke="#000" stroke-width="1.7" stroke-linecap="round"/>
<rect x="3" y="13" width="4.2" height="6.5" rx="1.6" stroke="#000" stroke-width="1.7"/>
<rect x="16.8" y="13" width="4.2" height="6.5" rx="1.6" stroke="#000" stroke-width="1.7"/>
</svg>''';

  static const telegram = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M21 4 3 11.3l5.6 1.9L11 20l3-4.2 4.5 3.3L21 4Z" stroke="#000" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>
<path d="M8.6 13.2 18 7" stroke="#000" stroke-width="1.4" stroke-linecap="round"/>
</svg>''';

  static const whatsapp = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M12 3.5a8.4 8.4 0 0 0-7.2 12.7L4 20.5l4.5-1.2A8.4 8.4 0 1 0 12 3.5Z" stroke="#000" stroke-width="1.5" stroke-linejoin="round"/>
<path d="M9 10.3c.4 2.4 2.3 4.3 4.7 4.7.6.1 1-.5 1-1v-.7c0-.3-.2-.6-.5-.7l-1.4-.5c-.3-.1-.6 0-.8.2l-.3.4a5 5 0 0 1-1.9-1.9l.4-.3c.2-.2.3-.5.2-.8l-.5-1.4a.7.7 0 0 0-.7-.5H8.6c-.5 0-1 .4-.9 1Z" stroke="#000" stroke-width="1.2" stroke-linejoin="round"/>
</svg>''';

  static const gift = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<rect x="3.5" y="9" width="17" height="4.5" rx="1" stroke="#000" stroke-width="1.6"/>
<path d="M5 13.5v6A1.5 1.5 0 0 0 6.5 21h11a1.5 1.5 0 0 0 1.5-1.5v-6" stroke="#000" stroke-width="1.6" stroke-linejoin="round"/>
<path d="M12 9v12M12 9C10 6 6 6 6 8.5S9 9 12 9ZM12 9c2-3 6-3 6-.5S15 9 12 9Z" stroke="#000" stroke-width="1.5" stroke-linejoin="round" stroke-linecap="round"/>
</svg>''';

  static const share = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<circle cx="18" cy="6" r="2.4" stroke="#000" stroke-width="1.6"/>
<circle cx="6" cy="12" r="2.4" stroke="#000" stroke-width="1.6"/>
<circle cx="18" cy="18" r="2.4" stroke="#000" stroke-width="1.6"/>
<path d="m8.1 10.8 7.8-3.6M8.1 13.2l7.8 3.6" stroke="#000" stroke-width="1.6" stroke-linecap="round"/>
</svg>''';

  static const chart = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M4 19V5M4 19h16" stroke="#000" stroke-width="1.6" stroke-linecap="round"/>
<path d="m6.5 15 3.5-4 3 2.3L18 8" stroke="#000" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>
</svg>''';

  static const search = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<circle cx="10.5" cy="10.5" r="6.5" stroke="#000" stroke-width="1.8"/>
<path d="m20 20-4.4-4.4" stroke="#000" stroke-width="1.8" stroke-linecap="round"/>
</svg>''';
}

/// Renders one of [SvgIcons]' strings, tinted to [color].
class SvgIcon extends StatelessWidget {
  const SvgIcon(this.data, {super.key, this.size = 22, this.color});

  final String data;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return SvgPicture.string(
      data,
      width: size,
      height: size,
      colorFilter: color == null
          ? null
          : ColorFilter.mode(color!, BlendMode.srcIn),
    );
  }
}

class CategoryDef {
  const CategoryDef(this.key, this.label, this.icon);
  final String key;
  final String label;
  final String icon;
}

const kCategories = [
  CategoryDef('deals', 'Deals', SvgIcons.deals),
  CategoryDef('all', 'All', SvgIcons.all),
  CategoryDef('beauty', 'Beauty', SvgIcons.beauty),
  CategoryDef('fashion', 'Fashion', SvgIcons.fashion),
  CategoryDef('health', 'Health', SvgIcons.health),
  CategoryDef('home', 'Home', SvgIcons.home),
  CategoryDef('electronics', 'Electronics', SvgIcons.electronics),
];
