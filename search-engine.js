// search-engine.js — DealBuster Intelligent Client-Side Search Engine
(function(root, factory) {
  if (typeof module === 'object' && module.exports) {
    module.exports = factory(require('./minisearch.min.js'));
  } else {
    root.DealSearch = factory(root.MiniSearch);
  }
}(typeof self !== 'undefined' ? self : this, function(MiniSearch) {
  'use strict';

  // 1. Bi-directional Synonym & Compound Dictionary
  const SYNONYM_GROUPS = [
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

  const SYNONYM_MAP = new Map();
  for (const group of SYNONYM_GROUPS) {
    for (const phrase of group) {
      const clean = phrase.toLowerCase().trim();
      const others = group.map(w => w.toLowerCase().trim()).filter(w => w !== clean);
      SYNONYM_MAP.set(clean, others);
    }
  }

  // 2. Singular / Plural English Stemmer
  function simpleStem(word) {
    if (!word || word.length <= 3) return word;
    const w = word.toLowerCase();
    if (w.endsWith('ies') && w.length > 4) return w.slice(0, -3) + 'y';
    if (w.endsWith('ves') && w.length > 4) return w.slice(0, -3) + 'f';
    if (w.endsWith('es') && w.length > 4) {
      if (/(?:ch|sh|ss|x|z)es$/.test(w)) return w.slice(0, -2);
      return w.slice(0, -1);
    }
    if (w.endsWith('s') && !w.endsWith('ss') && word.length > 3) {
      return w.slice(0, -1);
    }
    return w;
  }

  function processTerm(term) {
    const clean = term.toLowerCase().replace(/[^a-z0-9]/g, '');
    if (!clean || clean.length < 2) return null;
    return simpleStem(clean);
  }

  // Compound prefixes for dynamic decompounding (e.g. facewash -> face wash)
  const COMPOUND_PREFIXES = [
    'face', 'body', 'smart', 'power', 'ear', 'head', 'neck', 'water',
    'track', 'bed', 'hair', 'sound', 'air', 'shoe', 'back', 'hand',
    'sun', 'eye', 'lip', 'tooth', 'rain', 'wind'
  ];

  function getCompoundVariants(query) {
    const q = query.trim().toLowerCase();
    const variants = new Set();
    const tokens = q.split(/\s+/).filter(Boolean);

    // 1. Single word: check if it can be split, e.g. "facewash" -> "face wash"
    if (tokens.length === 1) {
      const t = tokens[0];
      for (const pre of COMPOUND_PREFIXES) {
        if (t.length >= pre.length + 3 && t.startsWith(pre)) {
          const rest = t.slice(pre.length);
          variants.add(pre + ' ' + rest);
        }
      }
    }

    // 2. Multi word: check if adjacent words can be joined, e.g. "face wash" -> "facewash"
    if (tokens.length >= 2) {
      for (let i = 0; i < tokens.length - 1; i++) {
        variants.add(tokens[i] + tokens[i + 1]);
      }
      variants.add(tokens.join(''));
    }

    return Array.from(variants);
  }

  // Common popular search keywords for suggestions
  const BASE_POPULAR_KEYWORDS = [
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

  class SearchEngine {
    constructor() {
      this.miniSearch = null;
      this.products = [];
      this.productByKey = new Map();
      this.suggestionDictionary = [];
      this.isReady = false;
    }

    init(products) {
      if (!Array.isArray(products) || !products.length) return;
      this.products = products;
      this.productByKey.clear();

      this.miniSearch = new MiniSearch({
        fields: ['title', 'category', 'brand', 'compounds'],
        storeFields: ['searchId', 'asin', 'link'],
        idField: 'searchId',
        processTerm: processTerm,
        searchOptions: {
          boost: { title: 3, compounds: 2.8, brand: 2.5, category: 1 },
          prefix: true,
          fuzzy: (term) => (term.length >= 8 ? 2 : (term.length >= 4 ? 1 : 0)),
          combineWith: 'AND'
        }
      });

      const docs = [];
      const phraseCounts = new Map();

      const addPhrase = (phrase, weight = 1) => {
        const clean = phrase.toLowerCase().replace(/[^a-z0-9\s]/g, '').trim().replace(/\s+/g, ' ');
        if (!clean || clean.length < 3 || /^\d+$/.test(clean)) return;
        phraseCounts.set(clean, (phraseCounts.get(clean) || 0) + weight);
      };

      // Seed with base keywords
      BASE_POPULAR_KEYWORDS.forEach(kw => addPhrase(kw, 50));

      for (let i = 0; i < products.length; i++) {
        const p = products[i];
        if (p.hidden) continue;
        const key = p.asin || p.link || ('p_' + i);
        this.productByKey.set(key, p);

        const title = p.title || '';
        const brandMatch = title.match(/^([A-Za-z0-9]+)/);
        const brand = brandMatch ? brandMatch[1] : '';

        // Generate compound terms from title:
        // e.g. "Face Wash" -> "facewash", "Power Bank" -> "powerbank", "Track Pants" -> "trackpants"
        const cleanWords = title.toLowerCase().replace(/[|,\-()/[\]]/g, ' ').match(/[a-z0-9]+/g) || [];
        const compounds = [];
        for (let j = 0; j < cleanWords.length - 1; j++) {
          const joined = cleanWords[j] + cleanWords[j + 1];
          if (joined.length >= 5 && joined.length <= 25) {
            compounds.push(joined);
          }
        }

        docs.push({
          searchId: key,
          asin: p.asin || '',
          link: p.link || '',
          title: title,
          category: p.category || '',
          brand: brand,
          compounds: compounds.join(' ')
        });

        // Extract clean 1-word and 2-word suggestion candidates
        const skip = new Set(['with', 'from', 'free', 'safe', 'door', 'star', 'pack', 'size', 'inch', 'plus', 'pro', 'max', 'offer', 'deal', 'coupon']);
        for (let j = 0; j < cleanWords.length; j++) {
          const w1 = cleanWords[j];
          if (w1.length >= 3 && !skip.has(w1)) {
            addPhrase(w1, 1);
            if (j < cleanWords.length - 1) {
              const w2 = cleanWords[j + 1];
              if (w2.length >= 3 && !skip.has(w2)) {
                addPhrase(`${w1} ${w2}`, 2);
              }
            }
          }
        }
      }

      this.miniSearch.addAll(docs);

      // Build top suggestions sorted by frequency
      this.suggestionDictionary = Array.from(phraseCounts.entries())
        .filter(([phrase, count]) => count >= 3 || BASE_POPULAR_KEYWORDS.includes(phrase))
        .sort((a, b) => b[1] - a[1])
        .map(([phrase]) => phrase);

      this.isReady = true;
    }

    search(query, maxResults = 80) {
      if (!this.isReady || !query || !query.trim()) return [];
      const rawQuery = query.trim().toLowerCase();
      const terms = rawQuery.match(/[a-z0-9]+/g) || [];
      if (!terms.length) return [];

      const searchFuzzy = (term) => (term.length >= 8 ? 2 : (term.length >= 4 ? 1 : 0));

      // 1. Direct search with typo-tolerance & prefix
      let directMatches = [];
      try {
        directMatches = this.miniSearch.search(rawQuery, {
          fuzzy: searchFuzzy,
          prefix: true,
          combineWith: 'AND'
        });
      } catch (e) {
        directMatches = [];
      }

      // If strict AND found few or 0 results for multi-word query, fallback to OR
      if (terms.length > 1 && directMatches.length < 5) {
        try {
          const orMatches = this.miniSearch.search(rawQuery, {
            fuzzy: searchFuzzy,
            prefix: true,
            combineWith: 'OR'
          });
          const existingIds = new Set(directMatches.map(m => m.id));
          for (const m of orMatches) {
            if (!existingIds.has(m.id)) {
              existingIds.add(m.id);
              directMatches.push(m);
            }
          }
        } catch (e) {}
      }

      // 2. Compound variants search (e.g. "facewash" -> "face wash", "face wash" -> "facewash")
      const compoundVariants = getCompoundVariants(rawQuery);
      const compoundMatches = [];
      for (const variant of compoundVariants) {
        try {
          const vMatches = this.miniSearch.search(variant, {
            fuzzy: searchFuzzy,
            prefix: true,
            combineWith: 'AND'
          });
          compoundMatches.push(...vMatches);
        } catch (e) {}
      }

      // 3. Synonym expansion
      const synonymResults = [];
      const seenSynonyms = new Set();
      const allQueryVariations = [rawQuery, ...compoundVariants, ...terms];

      for (const qVar of allQueryVariations) {
        const synList = SYNONYM_MAP.get(qVar) || SYNONYM_MAP.get(simpleStem(qVar)) || [];
        for (const syn of synList) {
          if (seenSynonyms.has(syn)) continue;
          seenSynonyms.add(syn);

          try {
            const matches = this.miniSearch.search(syn, {
              fuzzy: (t) => (t.length >= 8 ? 1 : 0),
              prefix: true,
              combineWith: 'AND'
            });
            synonymResults.push(...matches);
          } catch (e) {}
        }
      }

      // 4. Merge and deduplicate
      const scoreMap = new Map();
      for (const m of directMatches) {
        scoreMap.set(m.id, (scoreMap.get(m.id) || 0) + m.score * 2.0);
      }
      for (const m of compoundMatches) {
        scoreMap.set(m.id, (scoreMap.get(m.id) || 0) + m.score * 1.8);
      }
      for (const m of synonymResults) {
        scoreMap.set(m.id, (scoreMap.get(m.id) || 0) + m.score * 1.0);
      }

      const sortedIds = Array.from(scoreMap.entries())
        .sort((a, b) => b[1] - a[1])
        .slice(0, maxResults)
        .map(([id, score]) => ({
          id,
          score,
          product: this.productByKey.get(id)
        }))
        .filter(item => item.product);

      return sortedIds;
    }

    getSuggestions(query, limit = 6) {
      if (!this.isReady || !query || !query.trim()) return [];
      const q = query.trim().toLowerCase();
      if (q.length < 2) return [];

      const startsWith = [];
      const contains = [];
      const seen = new Set();

      for (const phrase of this.suggestionDictionary) {
        if (phrase === q) continue;
        if (seen.has(phrase)) continue;

        if (phrase.startsWith(q)) {
          seen.add(phrase);
          startsWith.push(phrase);
        } else if (phrase.includes(' ' + q)) {
          seen.add(phrase);
          contains.push(phrase);
        }
        if (startsWith.length >= limit) break;
      }

      return [...startsWith, ...contains].slice(0, limit);
    }
  }

  return new SearchEngine();
}));
