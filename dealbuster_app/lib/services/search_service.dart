import '../models/product.dart';

class SearchResult {
  final Product product;
  final double score;

  const SearchResult({required this.product, required this.score});
}

class SearchService {
  // Bi-directional Synonym & Compound Groups
  static final List<List<String>> _synonymGroups = [
    ['fridge', 'refrigerator', 'freezer', 'deepfreeze', 'minibar'],
    ['facewash', 'face wash', 'facial cleanser', 'cleanser'],
    ['bodywash', 'body wash', 'shower gel', 'bath gel'],
    ['bag', 'backpack', 'back pack', 'rucksack', 'duffle', 'knapsack', 'tote', 'handbag', 'hand bag', 'purse', 'sling'],
    ['shoe', 'shoes', 'footwear', 'sneaker', 'sneakers', 'boot', 'boots', 'sandal', 'sandals', 'crocs', 'slippers', 'chappal'],
    ['watch', 'watches', 'smartwatch', 'smart watches', 'smart watch', 'timepiece', 'wristwatch'],
    ['mobile', 'smartphone', 'phone', 'cellphone', 'handset'],
    ['tv', 'television', 'smarttv', 'smart tv', 'led tv', 'qled', 'oled'],
    ['earphone', 'earphones', 'ear phone', 'ear phones', 'earbud', 'earbuds', 'ear bud', 'ear buds', 'headphone', 'headphones', 'head phone', 'head phones', 'headset', 'airpods', 'tws', 'neckband', 'neck band', 'airdopes'],
    ['laptop', 'notebook', 'ultrabook', 'macbook', 'pc', 'computer'],
    ['ac', 'air conditioner', 'airconditioner', 'cooler', 'air cooler'],
    ['charger', 'adapter', 'powerbank', 'power bank', 'fast charger'],
    ['cable', 'cord', 'wire', 'type c', 'lightning', 'usb cable'],
    ['heater', 'geyser', 'waterheater', 'water heater', 'room heater'],
    ['shirt', 'tshirt', 't-shirt', 'tee', 'tees', 'top', 'polos'],
    ['pant', 'pants', 'trousers', 'jeans', 'trackpants', 'track pants', 'joggers', 'chinos'],
    ['bottle', 'flask', 'sipper', 'thermos', 'water bottle', 'waterbottle'],
    ['iron', 'dry iron', 'steam iron', 'garment steamer'],
    ['trimmer', 'shaver', 'groomer', 'clipper'],
    ['tablet', 'tab', 'ipad'],
    ['speaker', 'soundbar', 'sound bar', 'bluetooth speaker', 'home theatre'],
    ['purifier', 'water purifier', 'ro', 'aquaguard', 'air purifier', 'airpurifier'],
    ['shoerack', 'shoe rack'],
    ['bedsheet', 'bed sheet', 'bedsheets', 'bed sheets'],
    ['hairdryer', 'hair dryer'],
    ['sunscreen', 'sun screen'],
    ['toothpaste', 'tooth paste'],
    ['toothbrush', 'tooth brush'],
    ['raincoat', 'rain coat'],
    ['windcheater', 'wind cheater']
  ];

  static final Map<String, List<String>> _synonymMap = () {
    final map = <String, List<String>>{};
    for (final group in _synonymGroups) {
      for (final word in group) {
        final clean = word.toLowerCase().trim();
        map[clean] = group.where((w) => w.toLowerCase().trim() != clean).toList();
      }
    }
    return map;
  }();

  static const List<String> _compoundPrefixes = [
    'face', 'body', 'smart', 'power', 'ear', 'head', 'neck', 'water',
    'track', 'bed', 'hair', 'sound', 'air', 'shoe', 'back', 'hand',
    'sun', 'eye', 'lip', 'tooth', 'rain', 'wind'
  ];

  static List<String> _getCompoundVariants(String query) {
    final q = query.trim().toLowerCase();
    final variants = <String>{};
    final tokens = _tokenize(q);

    // 1. Single word: check if it can be split, e.g. "facewash" -> "face wash"
    if (tokens.length == 1) {
      final t = tokens[0];
      for (final pre in _compoundPrefixes) {
        if (t.length >= pre.length + 3 && t.startsWith(pre)) {
          final rest = t.substring(pre.length);
          variants.add('$pre $rest');
        }
      }
    }

    // 2. Multi word: check if adjacent words can be joined, e.g. "face wash" -> "facewash"
    if (tokens.length >= 2) {
      for (int i = 0; i < tokens.length - 1; i++) {
        variants.add('${tokens[i]}${tokens[i + 1]}');
      }
      variants.add(tokens.join(''));
    }

    return variants.toList();
  }

  static const List<String> _baseKeywords = [
    'iphone', 'iphone 15', 'iphone 16', 'apple', 'samsung', 'smartwatch', 'smart watch', 'watch',
    'facewash', 'face wash', 'body wash', 'bodywash', 'sunscreen',
    'shoes', 'sneakers', 'running shoes', 'crocs', 'slippers', 'sandals',
    'refrigerator', 'fridge', 'double door refrigerator', 'washing machine',
    'air conditioner', 'cooler', 'geyser', 'water heater',
    'backpack', 'bag', 'tote bag', 'handbag', 'luggage',
    'headphones', 'earbuds', 'earphones', 'tws', 'airpods', 'neckband',
    'laptop', 'gaming laptop', 'tablet', 'ipad',
    'power bank', 'powerbank', 'charger', 'type c cable', 'fast charger',
    't-shirt', 'shirt', 'jeans', 'trackpants', 'track pants', 'jacket',
    'water bottle', 'waterbottle', 'flask', 'trimmer', 'iron', 'steam iron'
  ];

  // Levenshtein distance for typo tolerance
  static int _levenshtein(String s, String t) {
    if (s == t) return 0;
    if (s.isEmpty) return t.length;
    if (t.isEmpty) return s.length;

    List<int> v0 = List<int>.filled(t.length + 1, 0);
    List<int> v1 = List<int>.filled(t.length + 1, 0);

    for (int i = 0; i <= t.length; i++) {
      v0[i] = i;
    }

    for (int i = 0; i < s.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < t.length; j++) {
        final cost = s[i] == t[j] ? 0 : 1;
        v1[j + 1] = [
          v1[j] + 1,
          v0[j + 1] + 1,
          v0[j] + cost,
        ].reduce((curr, next) => curr < next ? curr : next);
      }
      for (int j = 0; j <= t.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[t.length];
  }

  // Singular / Plural Stemmer
  static String simpleStem(String word) {
    if (word.length <= 3) return word;
    final w = word.toLowerCase();
    if (w.endsWith('ies') && w.length > 4) return '${w.substring(0, w.length - 3)}y';
    if (w.endsWith('ves') && w.length > 4) return '${w.substring(0, w.length - 3)}f';
    if (w.endsWith('es') && w.length > 4) {
      if (RegExp(r'(?:ch|sh|ss|x|z)es$').hasMatch(w)) {
        return w.substring(0, w.length - 2);
      }
      return w.substring(0, w.length - 1);
    }
    if (w.endsWith('s') && !w.endsWith('ss') && w.length > 3) {
      return w.substring(0, w.length - 1);
    }
    return w;
  }

  static List<String> _tokenize(String text) {
    return RegExp(r'[a-z0-9]+')
        .allMatches(text.toLowerCase())
        .map((m) => m.group(0)!)
        .where((t) => t.length >= 2)
        .toList();
  }

  // Smart search with typo-tolerance, stemming, synonyms, and compound words
  static List<Product> search(List<Product> products, String query) {
    final rawQuery = query.trim().toLowerCase();
    if (rawQuery.isEmpty) return [];

    final queryTerms = _tokenize(rawQuery);
    if (queryTerms.isEmpty) return [];

    final compoundVariants = _getCompoundVariants(rawQuery);

    // Build all query variations (original terms, compound split/joined terms, and synonyms)
    final allQueryVariations = <String>{rawQuery, ...compoundVariants, ...queryTerms};
    final synonymTerms = <String>{};

    for (final qVar in allQueryVariations) {
      final synList = _synonymMap[qVar] ?? _synonymMap[simpleStem(qVar)] ?? [];
      for (final syn in synList) {
        synonymTerms.add(syn);
        synonymTerms.addAll(_tokenize(syn));
      }
    }

    final compactQuery = rawQuery.replaceAll(RegExp(r'[^a-z0-9]'), '');
    final scored = <SearchResult>[];

    for (final p in products) {
      final title = p.title.toLowerCase();
      final titleTerms = _tokenize(title);
      final stemmedTitleTerms = titleTerms.map(simpleStem).toList();
      final compactTitle = title.replaceAll(RegExp(r'[^a-z0-9]'), '');

      double score = 0;
      bool matched = false;

      // 1. Direct space-insensitive compact match (e.g. "facewash" in "...neemfacewash...")
      if (compactQuery.length >= 4 && compactTitle.contains(compactQuery)) {
        score += 6.0;
        matched = true;
      }

      // Check compound variants compact matches (e.g. "face wash" -> compact "facewash")
      for (final cv in compoundVariants) {
        final compactCv = cv.replaceAll(RegExp(r'[^a-z0-9]'), '');
        if (compactCv.length >= 4 && compactTitle.contains(compactCv)) {
          score += 5.5;
          matched = true;
        }
      }

      // 2. Token-by-token evaluation against query terms
      int matchedTerms = 0;

      for (final qTerm in queryTerms) {
        final qStem = simpleStem(qTerm);
        final maxTypo = qTerm.length >= 8 ? 2 : (qTerm.length >= 4 ? 1 : 0);

        bool termMatched = false;
        double termScore = 0;

        // Exact word or substring match
        if (title.contains(qTerm)) {
          termMatched = true;
          termScore = 5.0;
        }

        // Token match or stem match
        if (!termMatched) {
          for (int i = 0; i < titleTerms.length; i++) {
            final tWord = titleTerms[i];
            final tStem = stemmedTitleTerms[i];

            if (tWord == qTerm || tStem == qStem) {
              termMatched = true;
              termScore = 4.5;
              break;
            }

            // Prefix match
            if (tWord.startsWith(qTerm) || tStem.startsWith(qStem)) {
              termMatched = true;
              termScore = 3.5;
              break;
            }

            // Fuzzy typo match
            if (maxTypo > 0) {
              final dist = _levenshtein(qTerm, tWord);
              if (dist <= maxTypo) {
                termMatched = true;
                termScore = 3.0 - (dist * 0.5);
                break;
              }
            }
          }
        }

        if (termMatched) {
          matchedTerms++;
          score += termScore;
        }
      }

      // 3. Synonym matches
      for (final syn in synonymTerms) {
        if (title.contains(syn) || compactTitle.contains(syn.replaceAll(RegExp(r'[^a-z0-9]'), ''))) {
          score += 2.5;
          matched = true;
        }
      }

      final minRequired = queryTerms.length > 2 ? queryTerms.length - 1 : queryTerms.length;
      if (matchedTerms >= minRequired || matched) {
        if (matchedTerms == queryTerms.length) score += 3.0;
        scored.add(SearchResult(product: p, score: score));
      }
    }

    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((s) => s.product).toList();
  }

  // Get Amazon/Flipkart-style search suggestions
  static List<String> getSuggestions(List<Product> products, String query, {int limit = 6}) {
    final q = query.trim().toLowerCase();
    if (q.length < 2) return [];

    final phraseSet = <String>{};
    // Seed with base popular keywords
    phraseSet.addAll(_baseKeywords);

    // Extract common 1-word and 2-word phrases from top products
    for (int i = 0; i < products.length && i < 200; i++) {
      final words = _tokenize(products[i].title);
      for (int j = 0; j < words.length; j++) {
        if (words[j].length >= 3) {
          phraseSet.add(words[j]);
          if (j < words.length - 1 && words[j + 1].length >= 3) {
            phraseSet.add('${words[j]} ${words[j + 1]}');
          }
        }
      }
    }

    final startsWith = <String>[];
    final contains = <String>[];

    for (final phrase in phraseSet) {
      if (phrase == q) continue;
      if (phrase.startsWith(q)) {
        startsWith.add(phrase);
      } else if (phrase.contains(' $q')) {
        contains.add(phrase);
      }
      if (startsWith.length >= limit) break;
    }

    return [...startsWith, ...contains].take(limit).toList();
  }
}
