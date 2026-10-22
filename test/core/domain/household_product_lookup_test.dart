import 'package:flutter_test/flutter_test.dart';
import 'package:providentia/core/domain/household_product_lookup.dart';

void main() {
  const lookup = HouseholdProductLookup();

  List<ProductLookupText> search(
    String query,
    Iterable<ProductLookupText> products,
  ) => lookup.rank(query: query, products: products, describe: (item) => item);

  test(
    'exact names and known aliases precede partial and metadata matches',
    () {
      const alias = ProductLookupText(
        name: 'Mieliemeel',
        aliases: <String>['Maize meal'],
      );
      const partial = ProductLookupText(name: 'Maize meal coarse');
      const metadata = ProductLookupText(
        name: 'Pantry staple',
        category: 'Maize meal',
      );
      expect(
        search('  MAIZE   MEAL  ', <ProductLookupText>[
          metadata,
          partial,
          alias,
        ]),
        <ProductLookupText>[alias, partial, metadata],
      );
    },
  );

  test(
    'brand, category and pack tokens accept useful partial-word queries',
    () {
      const matching = ProductLookupText(
        name: 'Basmati rice',
        brand: 'Tastic',
        category: 'Grains',
        pack: '5 kg',
      );
      const otherPack = ProductLookupText(
        name: 'Basmati rice',
        brand: 'Tastic',
        category: 'Grains',
        pack: '1 kg',
      );
      expect(
        search('bas 5 kg gra', <ProductLookupText>[otherPack, matching]),
        <ProductLookupText>[matching],
      );
      expect(
        search('tas bas', <ProductLookupText>[matching]),
        <ProductLookupText>[matching],
      );
    },
  );

  test('brand and product names can be entered together in either order', () {
    const matching = ProductLookupText(name: 'Apples', brand: 'Sunfresh');
    const partial = ProductLookupText(
      name: 'Apples pie filling',
      brand: 'Sunfresh',
    );
    for (final query in <String>['Sunfresh Apples', 'Apples Sunfresh']) {
      expect(
        search(query, <ProductLookupText>[partial, matching]).first,
        same(matching),
      );
    }
  });

  test('empty browse sorts by name, brand and pack with stable ties', () {
    const rice = ProductLookupText(name: 'Rice');
    const teaZ = ProductLookupText(name: 'Tea', brand: 'Zed', pack: '20 bags');
    const teaA40 = ProductLookupText(
      name: 'tea',
      brand: 'Alpha',
      pack: '40 bags',
    );
    const teaA20 = ProductLookupText(
      name: 'TEA',
      brand: 'Alpha',
      pack: '20 bags',
    );
    final tie = ProductLookupText(name: 'TEA', brand: 'Alpha', pack: '20 bags');
    expect(
      search('', <ProductLookupText>[teaZ, teaA40, teaA20, tie, rice]),
      <ProductLookupText>[rice, teaA20, tie, teaA40, teaZ],
    );
  });

  test(
    'accented names remain searchable and returned values stay unchanged',
    () {
      const coffee = ProductLookupText(
        name: 'Café crème',
        aliases: <String>['Coffee cream'],
      );
      expect(search('CAFÉ', <ProductLookupText>[coffee]), <ProductLookupText>[
        coffee,
      ]);
      expect(
        search('coffee cream', <ProductLookupText>[coffee]).single,
        same(coffee),
      );
      expect(coffee.name, 'Café crème');
    },
  );

  test('unknown searches do not offer unrelated products', () {
    expect(
      search('unrelated', const <ProductLookupText>[
        ProductLookupText(name: 'Rice'),
        ProductLookupText(name: 'Tea'),
      ]),
      isEmpty,
    );
  });
}
