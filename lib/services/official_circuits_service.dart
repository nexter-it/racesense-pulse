import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/official_circuit_info.dart';

/// Servizio singleton per caricare e gestire i circuiti ufficiali dal file JSON.
/// I circuiti vengono caricati una sola volta e poi cachati in memoria.
class OfficialCircuitsService {
  static final OfficialCircuitsService _instance =
      OfficialCircuitsService._internal();
  factory OfficialCircuitsService() => _instance;
  OfficialCircuitsService._internal();

  List<OfficialCircuitInfo>? _cachedCircuits;
  String? _version;
  String? _lastUpdated;

  /// Carica tutti i circuiti dal file JSON asset
  Future<List<OfficialCircuitInfo>> loadCircuits() async {
    if (_cachedCircuits != null) return _cachedCircuits!;

    final jsonString =
        await rootBundle.loadString('assets/data/official_circuits.json');
    final jsonData = json.decode(jsonString) as Map<String, dynamic>;

    _version = jsonData['version'] as String?;
    _lastUpdated = jsonData['lastUpdated'] as String?;

    final circuitsJson = jsonData['circuits'] as List<dynamic>;

    _cachedCircuits = circuitsJson
        .map((c) => OfficialCircuitInfo.fromJson(c as Map<String, dynamic>))
        .toList();

    // Ordina per nome
    _cachedCircuits!.sort((a, b) => a.name.compareTo(b.name));

    return _cachedCircuits!;
  }

  /// Versione del file JSON
  String? get version => _version;

  /// Data ultimo aggiornamento
  String? get lastUpdated => _lastUpdated;

  /// Ottieni circuiti filtrati per paese
  Future<List<OfficialCircuitInfo>> getByCountry(String countryCode) async {
    final all = await loadCircuits();
    return all
        .where((c) => c.countryCode.toLowerCase() == countryCode.toLowerCase())
        .toList();
  }

  /// Ottieni circuiti filtrati per continente
  Future<List<OfficialCircuitInfo>> getByContinent(String continent) async {
    final all = await loadCircuits();
    return all
        .where((c) => c.continent.toLowerCase() == continent.toLowerCase())
        .toList();
  }

  /// Ottieni circuiti filtrati per categoria
  Future<List<OfficialCircuitInfo>> getByCategory(String category) async {
    final all = await loadCircuits();
    return all
        .where((c) =>
            c.category?.toLowerCase() == category.toLowerCase())
        .toList();
  }

  /// Cerca circuiti per nome (case-insensitive, partial match)
  Future<List<OfficialCircuitInfo>> search(String query) async {
    if (query.isEmpty) return loadCircuits();

    final all = await loadCircuits();
    final q = query.toLowerCase();

    return all.where((c) {
      return c.name.toLowerCase().contains(q) ||
          c.city.toLowerCase().contains(q) ||
          c.country.toLowerCase().contains(q);
    }).toList();
  }

  /// Trova un circuito per ID
  Future<OfficialCircuitInfo?> findById(String id) async {
    final all = await loadCircuits();
    try {
      return all.firstWhere((c) => c.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Ottieni tutte le categorie disponibili
  Future<List<String>> getCategories() async {
    final all = await loadCircuits();
    final categories = <String>{};
    for (final c in all) {
      if (c.category != null) {
        categories.add(c.category!);
      }
    }
    return categories.toList()..sort();
  }

  /// Ottieni tutti i paesi disponibili
  Future<List<String>> getCountries() async {
    final all = await loadCircuits();
    final countries = <String>{};
    for (final c in all) {
      countries.add(c.country);
    }
    return countries.toList()..sort();
  }

  /// Numero totale di circuiti
  Future<int> get count async {
    final all = await loadCircuits();
    return all.length;
  }

  /// Pulisci la cache (per testing/refresh)
  void clearCache() {
    _cachedCircuits = null;
    _version = null;
    _lastUpdated = null;
  }
}
