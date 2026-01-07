/// Modello per le informazioni pubbliche del pilota
/// Visibili nella bacheca profilo personale e profili ricercati
class DriverInfo {
  final List<String> selectedBadges;
  final String bio;

  DriverInfo({
    required this.selectedBadges,
    required this.bio,
  });

  /// Badge disponibili per categoria
  static const Map<String, List<Map<String, String>>> badgeCategories = {
    'Status/Obiettivi': [
      {'id': 'cerco_sponsor', 'label': 'Cerco Sponsor'},
      {'id': 'amatoriale', 'label': 'Pilota Amatoriale'},
      {'id': 'professionista', 'label': 'Pilota Professionista'},
      {'id': 'in_formazione', 'label': 'In Formazione'},
      {'id': 'competizioni', 'label': 'Competizioni Attive'},
    ],
    'Specializzazione': [
      {'id': 'karting', 'label': 'Karting'},
      {'id': 'moto', 'label': 'Moto'},
      {'id': 'auto_corsa', 'label': 'Auto da Corsa'},
      {'id': 'rally', 'label': 'Rally'},
      {'id': 'track_day', 'label': 'Track Day'},
    ],
    'Disponibilità': [
      {'id': 'disponibile_eventi', 'label': 'Disponibile per Eventi'},
      {'id': 'cerco_team', 'label': 'Cerco Team'},
      {'id': 'collaborazioni', 'label': 'Aperto a Collaborazioni'},
    ],
  };

  /// Ottieni tutti i badge disponibili (flat list)
  static List<String> get allAvailableBadges {
    final List<String> badges = [];
    badgeCategories.forEach((category, badgeList) {
      badges.addAll(badgeList.map((b) => b['id']!));
    });
    return badges;
  }

  /// Ottieni label da badge ID
  static String getLabelForBadge(String badgeId) {
    for (var category in badgeCategories.values) {
      for (var badge in category) {
        if (badge['id'] == badgeId) {
          return badge['label']!;
        }
      }
    }
    return badgeId;
  }

  /// Ottieni categoria da badge ID
  static String? getCategoryForBadge(String badgeId) {
    for (var entry in badgeCategories.entries) {
      for (var badge in entry.value) {
        if (badge['id'] == badgeId) {
          return entry.key;
        }
      }
    }
    return null;
  }

  /// Validazione bio (max 100 caratteri)
  static String? validateBio(String bio) {
    if (bio.length > 100) {
      return 'La bio deve essere al massimo 100 caratteri';
    }
    return null;
  }

  /// Crea DriverInfo vuoto
  factory DriverInfo.empty() {
    return DriverInfo(
      selectedBadges: [],
      bio: '',
    );
  }

  /// Serializzazione per Firebase
  Map<String, dynamic> toJson() {
    return {
      'selectedBadges': selectedBadges,
      'bio': bio,
    };
  }

  /// Deserializzazione da Firebase
  factory DriverInfo.fromJson(Map<String, dynamic> json) {
    return DriverInfo(
      selectedBadges: (json['selectedBadges'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      bio: json['bio'] as String? ?? '',
    );
  }

  /// Copia con modifiche
  DriverInfo copyWith({
    List<String>? selectedBadges,
    String? bio,
  }) {
    return DriverInfo(
      selectedBadges: selectedBadges ?? this.selectedBadges,
      bio: bio ?? this.bio,
    );
  }

  /// Verifica se ha almeno un badge selezionato
  bool get hasBadges => selectedBadges.isNotEmpty;

  /// Verifica se ha bio
  bool get hasBio => bio.trim().isNotEmpty;

  /// Verifica se ha almeno una info
  bool get hasAnyInfo => hasBadges || hasBio;
}
