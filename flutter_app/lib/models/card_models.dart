/// Scryfall card model — only fields we actually use.
class ScryfallCard {
  final String name;
  final String scryfallId;
  final String? imageUriNormal;
  final String? imageUriPng;
  final String? imageUriLarge;
  final String typeLine;
  final String oracleText;
  final List<String> colorIdentity;
  final List<String> games; // ["paper", "arena", "mtgo"]
  final Map<String, String> legalities; // {"timeless": "legal", ...}
  final List<CardFace>? cardFaces; // double-faced cards
  final int quantity;
  final int? mtgoId; // MTGO CatID (Scryfall: mtgo_id)

  const ScryfallCard({
    required this.name,
    required this.scryfallId,
    this.imageUriNormal,
    this.imageUriPng,
    this.imageUriLarge,
    this.typeLine = '',
    this.oracleText = '',
    this.colorIdentity = const [],
    this.games = const ['paper'],
    this.legalities = const {},
    this.cardFaces,
    this.quantity = 1,
    this.mtgoId,
  });

  String get bestImageUri =>
      imageUriPng ?? imageUriLarge ?? imageUriNormal ?? '';



  bool get isLegalInArena => 
      games.contains('arena') || 
      (legalities['timeless'] != null && legalities['timeless'] != 'not_legal');

  bool get isLegalInMtgo  => 
      games.contains('mtgo') || 
      mtgoId != null || 
      (legalities['vintage'] != null && legalities['vintage'] != 'not_legal');

  factory ScryfallCard.fromJson(Map<String, dynamic> json, {int quantity = 1}) {
    List<CardFace>? faces;
    if (json['card_faces'] != null) {
      faces = (json['card_faces'] as List)
          .map((f) => CardFace.fromJson(f as Map<String, dynamic>))
          .toList();
    }

    final imgUris = json['image_uris'] as Map<String, dynamic>?;

    return ScryfallCard(
      name:           json['name'] as String? ?? '',
      scryfallId:     json['id'] as String? ?? '',
      imageUriNormal: imgUris?['normal'] as String?,
      imageUriPng:    imgUris?['png'] as String?,
      imageUriLarge:  imgUris?['large'] as String?,
      typeLine:       json['type_line'] as String? ?? '',
      oracleText:     json['oracle_text'] as String? ?? '',
      colorIdentity:  (json['color_identity'] as List?)?.cast<String>() ?? [],
      games:          (json['games'] as List?)?.cast<String>() ?? ['paper'],
      legalities:     (json['legalities'] as Map<String, dynamic>?)?.map((k, v) => MapEntry(k, v.toString())) ?? {},
      cardFaces:      faces,
      quantity:       quantity,
      mtgoId:         json['mtgo_id'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'id': scryfallId,
    'type_line': typeLine,
    'oracle_text': oracleText,
    'color_identity': colorIdentity,
    'games': games,
    'quantity': quantity,
    if (bestImageUri.isNotEmpty) 'image_uri': bestImageUri,
  };
}

class CardFace {
  final String name;
  final String? imageUriNormal;
  final String? imageUriPng;
  final String oracleText;

  const CardFace({
    required this.name,
    this.imageUriNormal,
    this.imageUriPng,
    this.oracleText = '',
  });

  String get bestImageUri => imageUriPng ?? imageUriNormal ?? '';

  factory CardFace.fromJson(Map<String, dynamic> json) {
    final imgs = json['image_uris'] as Map<String, dynamic>?;
    return CardFace(
      name:           json['name'] as String? ?? '',
      imageUriNormal: imgs?['normal'] as String?,
      imageUriPng:    imgs?['png'] as String?,
      oracleText:     json['oracle_text'] as String? ?? '',
    );
  }
}

/// Lightweight commander entry from EDHREC browse/random endpoints.
class Commander {
  final String name;
  final String slug;
  final String? imageUri;
  final List<String> colorIdentity;

  const Commander({
    required this.name,
    required this.slug,
    this.imageUri,
    this.colorIdentity = const [],
  });

  factory Commander.fromEdhrecJson(Map<String, dynamic> json) {
    return Commander(
      name:          json['name'] as String? ?? '',
      slug:          json['sanitized'] as String? ?? '',
      imageUri:      json['image_uris']?['normal'] as String?,
      colorIdentity: (json['color_identity'] as List?)?.cast<String>() ?? [],
    );
  }
}

/// EDHREC recommendation card entry.
class EdhrecCard {
  final String name;
  final String category;   // e.g. "Card Draw and Advantage"
  final String symbol;     // e.g. "D", "M", "R"
  final String? imageUri;

  const EdhrecCard({
    required this.name,
    required this.category,
    required this.symbol,
    this.imageUri,
  });
}

// ── Proxy Print Card ──────────────────────────────────────────────────────────

/// A card entry in the Deck Builder / Proxy Print pipeline.
/// Wraps the raw Scryfall JSON so all fields are available to the PDF engine.
class ProxyCard {
  final Map<String, dynamic> scryfallData;
  int quantity;

  /// Path to a user-supplied local image file. When non-null, overrides
  /// both the Scryfall and MTGPics image sources in the PDF generator.
  String? localImagePath;

  ProxyCard({
    required this.scryfallData,
    this.quantity = 1,
    this.localImagePath,
  });

  String get name => scryfallData['name'] as String? ?? 'Unknown';
  String get setCode => scryfallData['set'] as String? ?? '';
  String get collectorNumber => scryfallData['collector_number'] as String? ?? '';
  num get cmc => scryfallData['cmc'] as num? ?? 0;
  String get usdPrice =>
      (scryfallData['prices'] as Map?)?['usd'] as String? ?? '0.00';
}
