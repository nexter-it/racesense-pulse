import 'package:flutter/material.dart';

import '../models/session_model.dart';
import '../services/session_service.dart';
import '../theme.dart';
import 'activity_detail_page.dart';

class SearchTrackSessionsPage extends StatefulWidget {
  final String trackName;
  final List<SessionModel> preloaded;

  const SearchTrackSessionsPage({
    super.key,
    required this.trackName,
    this.preloaded = const [],
  });

  @override
  State<SearchTrackSessionsPage> createState() =>
      _SearchTrackSessionsPageState();
}

class _SearchTrackSessionsPageState extends State<SearchTrackSessionsPage> {
  final SessionService _sessionService = SessionService();

  bool _loading = false;
  List<SessionModel> _sessions = [];

  @override
  void initState() {
    super.initState();
    _sessions = widget.preloaded;
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
    });
    try {
      final data = await _sessionService.getPublicSessionsByTrack(
        widget.trackName,
        limit: 50,
      );
      if (mounted) {
        setState(() {
          _sessions = data;
        });
      }
    } catch (_) {
      // silenzioso
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatLap(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    final millis = (d.inMilliseconds % 1000) ~/ 10;
    return '$minutes:${seconds.toString().padLeft(2, '0')}.${millis.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.trackName),
      ),
      body: RefreshIndicator(
        onRefresh: _loadSessions,
        color: kBrandColor,
        child: _loading && _sessions.isEmpty
            ? const Center(
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(kBrandColor),
                ),
              )
            : ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: _sessions.length,
                itemBuilder: (context, index) {
                  final s = _sessions[index];
                  final bestLapStr =
                      s.bestLap != null ? _formatLap(s.bestLap!) : '--:--.--';
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10121A),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kLineColor),
                    ),
                    child: ListTile(
                      title: Text(
                        s.trackName,
                        style: const TextStyle(
                            color: kFgColor, fontWeight: FontWeight.w800),
                      ),
                      subtitle: Text(
                        '${s.location} · ${s.dateTime.toLocal().toIso8601String().substring(0, 10)}',
                        style: const TextStyle(color: kMutedColor, fontSize: 12),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '${s.distanceKm.toStringAsFixed(1)} km',
                            style: const TextStyle(
                                color: kBrandColor,
                                fontWeight: FontWeight.w700,
                                fontSize: 13),
                          ),
                          Text(
                            'Best $bestLapStr',
                            style: const TextStyle(
                                color: kMutedColor, fontSize: 11),
                          ),
                        ],
                      ),
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const ActivityDetailPage(),
                            settings:
                                RouteSettings(arguments: s),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}
