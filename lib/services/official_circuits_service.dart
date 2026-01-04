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

  /// Carica tutti i circuiti dal file JSON asset
  Future<List<OfficialCircuitInfo>> loadCircuits() async {
    if (_cachedCircuits != null) return _cachedCircuits!;

    final jsonString =
        await rootBundle.loadString('assets/data/start_lines_italia.json');
    final circuitsJson = json.decode(jsonString) as List<dynamic>;

    _cachedCircuits = circuitsJson
        .map((c) => OfficialCircuitInfo.fromJson(c as Map<String, dynamic>))
        .toList();

    // Ordina per nome
    _cachedCircuits!.sort((a, b) => a.name.compareTo(b.name));

    return _cachedCircuits!;
  }

  /// Ottieni circuiti filtrati per paese
  Future<List<OfficialCircuitInfo>> getByCountry(String country) async {
    final all = await loadCircuits();
    return all
        .where((c) => c.country.toLowerCase() == country.toLowerCase())
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
  }
}
