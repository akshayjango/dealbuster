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

  /// The torn-corner discount badge — pre-baked with a brand gradient
  /// (unlike the other icons here, this one carries its own color).
  static const discountBadge = '''
<svg width="110" height="109" viewBox="0 0 110 109" fill="none" xmlns="http://www.w3.org/2000/svg">
<defs>
<linearGradient id="discountBadgeGrad" x1="0" y1="0" x2="110" y2="109" gradientUnits="userSpaceOnUse">
<stop offset="0" stop-color="#FF8259"/>
<stop offset="1" stop-color="#E8431F"/>
</linearGradient>
</defs>
<path d="M87.2793 0C88.4037 1.42926e-05 89.5054 0.316178 90.459 0.912109L101.355 7.72168C103.535 9.08375 104.604 11.6831 104.016 14.1846L103.766 15.2461C103.29 17.2687 103.894 19.394 105.363 20.8633L108.14 23.6396C110.108 25.6085 110.465 28.6736 108.999 31.041L106.504 35.0703C105.553 36.6074 105.345 38.4918 105.938 40.1992L107.879 45.7754C108.574 47.7746 108.164 49.9923 106.801 51.6113L102.41 56.8252C101.499 57.9068 101 59.2755 101 60.6895V66.792C101 69.0644 99.7161 71.1418 97.6836 72.1582L91.4688 75.2656C89.9023 76.0489 88.756 77.4777 88.3311 79.1768L86.4609 86.6562C85.8781 88.9874 83.9606 90.7463 81.5879 91.126L75.8154 92.0498C74.0339 92.335 72.4753 93.4064 71.5713 94.9678L69.2334 99.0059C68.1607 100.859 66.1819 102 64.041 102H55.8164C54.6319 102 53.4738 102.351 52.4883 103.008L46.2217 107.186C44.5254 108.316 42.3706 108.509 40.501 107.696L34.5059 105.089C32.9142 104.397 31.1002 104.429 29.5332 105.175L25.3262 107.178C23.0329 108.27 20.3001 107.8 18.5039 106.004L16.2578 103.758C15.1326 102.633 13.6059 102 12.0146 102H9.28125C6.97069 102 4.86507 100.673 3.86816 98.5889L0.586914 91.7275C0.200453 90.9194 0 90.0345 0 89.1387V0H87.2793Z" fill="url(#discountBadgeGrad)"/>
</svg>''';

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
<path d="M8.7 7.70039L11 5.40039V15.0004C11 15.6004 11.4 16.0004 12 16.0004C12.6 16.0004 13 15.6004 13 15.0004V5.40039L15.3 7.70039C15.7 8.10039 16.3 8.10039 16.7 7.70039C17.1 7.30039 17.1 6.70039 16.7 6.30039L12.7 2.30039C12.6 2.20039 12.5 2.10039 12.4 2.10039C12.2 2.00039 11.9 2.00039 11.6 2.10039C11.5 2.10039 11.4 2.20039 11.3 2.30039L7.3 6.30039C6.9 6.70039 6.9 7.30039 7.3 7.70039C7.7 8.10039 8.3 8.10039 8.7 7.70039ZM21 14.0004C20.4 14.0004 20 14.4004 20 15.0004V19.0004C20 19.6004 19.6 20.0004 19 20.0004H5C4.4 20.0004 4 19.6004 4 19.0004V15.0004C4 14.4004 3.6 14.0004 3 14.0004C2.4 14.0004 2 14.4004 2 15.0004V19.0004C2 20.7004 3.3 22.0004 5 22.0004H19C20.7 22.0004 22 20.7004 22 19.0004V15.0004C22 14.4004 21.6 14.0004 21 14.0004Z" fill="#000"/>
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

  static const close = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M6.5 6.5 17.5 17.5M17.5 6.5 6.5 17.5" stroke="#000" stroke-width="2.4" stroke-linecap="round"/>
</svg>''';

  static const tag = '''
<svg viewBox="0 0 24 24" fill="none" xmlns="http://www.w3.org/2000/svg">
<path d="M12.6 2.6a2 2 0 0 0-1.4-.6H4a2 2 0 0 0-2 2v7.2a2 2 0 0 0 .6 1.4l8.7 8.7a2 2 0 0 0 2.8 0l6.6-6.6a2 2 0 0 0 0-2.8Z" stroke="#000" stroke-width="1.6" stroke-linejoin="round" stroke-linecap="round"/>
<circle cx="7.5" cy="7.5" r="1.1" fill="#000"/>
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
