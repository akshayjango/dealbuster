import 'dart:convert';
import 'package:dealbuster_app/services/api_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ApiService.parseProductsSync filters hidden, OOS, zero-price and upto-discount items', () {
    final testJson = jsonEncode([
      {
        'id': 'p1',
        'title': 'Valid Product Deal',
        'price': '₹499',
        'mrp': '₹999',
        'disc': '50% off',
        'image': 'https://example.com/p1.jpg',
        'link': 'https://amazon.in/dp/B001',
        'category': 'electronics',
        'featured': false,
        'hidden': false,
        'outOfStock': false,
      },
      {
        'id': 'p2',
        'title': 'Hidden Product Deal',
        'price': '₹499',
        'mrp': '₹999',
        'disc': '50% off',
        'image': 'https://example.com/p2.jpg',
        'link': 'https://amazon.in/dp/B002',
        'category': 'electronics',
        'featured': false,
        'hidden': true,
        'outOfStock': false,
      },
      {
        'id': 'p3',
        'title': 'OOS Product Deal',
        'price': '₹499',
        'mrp': '₹999',
        'disc': '50% off',
        'image': 'https://example.com/p3.jpg',
        'link': 'https://amazon.in/dp/B003',
        'category': 'electronics',
        'featured': false,
        'hidden': false,
        'outOfStock': true,
      },
      {
        'id': 'p4',
        'title': 'Zero Price Product Deal',
        'price': '₹0',
        'mrp': '₹999',
        'disc': '100% off',
        'image': 'https://example.com/p4.jpg',
        'link': 'https://amazon.in/dp/B004',
        'category': 'electronics',
        'featured': false,
        'hidden': false,
        'outOfStock': false,
      },
      {
        'id': 'p5',
        'title': 'Clothing Upto 70% Off Sale',
        'price': '₹299',
        'mrp': '₹999',
        'disc': '70% off',
        'image': 'https://example.com/p5.jpg',
        'link': 'https://amazon.in/dp/B005',
        'category': 'fashion',
        'featured': false,
        'hidden': false,
        'outOfStock': false,
      },
    ]);

    final products = ApiService.parseProductsSync(testJson);
    expect(products.length, 1);
    expect(products.first.id, 'p1');
    expect(products.first.title, 'Valid Product Deal');
  });
}
