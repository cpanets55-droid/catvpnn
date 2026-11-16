import 'package:flutter/material.dart';
import '../models/nord_models.dart';
import '../services/nord_api_service.dart';

class ServerSelectionResult {
  final NordCountry? country; // null = Smart Fastest Global
  final NordServer? specificServer;

  const ServerSelectionResult({this.country, this.specificServer});
}

class ServerPickerSheet extends StatefulWidget {
  final List<NordCountry> countries;
  final NordCountry? selectedCountry;
  final NordServer? activeServer;

  const ServerPickerSheet({
    super.key,
    required this.countries,
    required this.selectedCountry,
    required this.activeServer,
  });

  @override
  State<ServerPickerSheet> createState() => _ServerPickerSheetState();
}

class _ServerPickerSheetState extends State<ServerPickerSheet> {
  String _query = '';
  int? _expandedCountryId;
  bool _loadingNodes = false;
  List<NordServer> _countryNodes = const [];

  Future<void> _loadNodesForCountry(NordCountry country) async {
    if (_expandedCountryId == country.id) {
      setState(() {
        _expandedCountryId = null;
        _countryNodes = const [];
      });
      return;
    }

    setState(() {
      _expandedCountryId = country.id;
      _loadingNodes = true;
      _countryNodes = const [];
    });

    try {
      final nodes = await NordApiService.fetchRecommendedServers(
        countryId: country.id,
        limit: 15,
      );
      if (!mounted) return;
      setState(() {
        _countryNodes = nodes;
        _loadingNodes = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingNodes = false;
      });
    }
  }

  Color _loadColor(int load) {
    if (load < 35) return const Color(0xFF00F5A0);
    if (load < 70) return const Color(0xFFFBBF24);
    return const Color(0xFFFB7185);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final filtered = widget.countries.where((c) {
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.code.toLowerCase().contains(q);
    }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.86,
      minChildSize: 0.55,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0E1222),
            borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    const Text(
                      'Chọn Quốc Gia • NordLynx',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF7C5CFF).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${widget.countries.length} nước',
                        style: const TextStyle(
                          color: Color(0xFFBBA8FF),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  style: const TextStyle(color: Colors.white),
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Tìm quốc gia (VD: Vietnam, Singapore, Japan, US...)',
                    hintStyle: const TextStyle(
                      color: Colors.white38,
                      fontSize: 14,
                    ),
                    prefixIcon: const Icon(Icons.search, color: Colors.white54),
                    filled: true,
                    fillColor: const Color(0xFF171C33),
                    contentPadding: const EdgeInsets.symmetric(vertical: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  itemCount: filtered.length + (q.isEmpty ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (q.isEmpty && index == 0) {
                      final isSmartSelected = widget.selectedCountry == null;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF00F5A0).withValues(alpha: 0.16),
                              const Color(0xFF38BDF8).withValues(alpha: 0.12),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isSmartSelected
                                ? const Color(0xFF00F5A0)
                                : Colors.white12,
                          ),
                        ),
                        child: ListTile(
                          onTap: () => Navigator.of(context).pop(
                            const ServerSelectionResult(country: null),
                          ),
                          leading: const Text(
                            '⚡',
                            style: TextStyle(fontSize: 26),
                          ),
                          title: const Text(
                            'Tự động nhanh nhất (Smart Connect)',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: const Text(
                            'Tự chọn server ping & tải thấp nhất gần bạn',
                            style: TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                          trailing: isSmartSelected
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Color(0xFF00F5A0),
                                )
                              : const Icon(
                                  Icons.chevron_right,
                                  color: Colors.white54,
                                ),
                        ),
                      );
                    }

                    final country = filtered[q.isEmpty ? index - 1 : index];
                    final isSelected = widget.selectedCountry?.id == country.id;
                    final isExpanded = _expandedCountryId == country.id;
                    final isPinned = NordApiService.pinnedCountryCodes
                        .contains(country.code.toUpperCase());

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF151A30),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFF00F5A0)
                              : Colors.white10,
                        ),
                      ),
                      child: Column(
                        children: [
                          ListTile(
                            onTap: () => Navigator.of(context).pop(
                              ServerSelectionResult(country: country),
                            ),
                            leading: Text(
                              country.flag,
                              style: const TextStyle(fontSize: 26),
                            ),
                            title: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    country.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                if (isPinned) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'HOT',
                                      style: TextStyle(
                                        color: Colors.amberAccent,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              'Mã: ${country.code} • Chạm để nối nhanh',
                              style: const TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                            trailing: IconButton(
                              tooltip: 'Chọn từng node',
                              onPressed: () => _loadNodesForCountry(country),
                              icon: Icon(
                                isExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.dns_outlined,
                                color: isExpanded
                                    ? const Color(0xFF38BDF8)
                                    : Colors.white54,
                              ),
                            ),
                          ),
                          if (isExpanded)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                              child: _loadingNodes
                                  ? const Padding(
                                      padding: EdgeInsets.all(14),
                                      child: Center(
                                        child: SizedBox(
                                          width: 22,
                                          height: 22,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            color: Color(0xFF38BDF8),
                                          ),
                                        ),
                                      ),
                                    )
                                  : _countryNodes.isEmpty
                                      ? const Padding(
                                          padding: EdgeInsets.all(8.0),
                                          child: Text(
                                            'Không có node WireGuard khả dụng.',
                                            style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12,
                                            ),
                                          ),
                                        )
                                      : Column(
                                          children: _countryNodes.map((srv) {
                                            final active =
                                                widget.activeServer?.id ==
                                                    srv.id;
                                            return InkWell(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              onTap: () =>
                                                  Navigator.of(context).pop(
                                                ServerSelectionResult(
                                                  country: country,
                                                  specificServer: srv,
                                                ),
                                              ),
                                              child: Container(
                                                margin: const EdgeInsets.only(
                                                  top: 6,
                                                ),
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10,
                                                ),
                                                decoration: BoxDecoration(
                                                  color: active
                                                      ? const Color(0xFF00F5A0)
                                                          .withValues(alpha: 0.14)
                                                      : const Color(0xFF0F1325),
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.bolt,
                                                      size: 16,
                                                      color: _loadColor(
                                                        srv.load,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 8),
                                                    Expanded(
                                                      child: Column(
                                                        crossAxisAlignment:
                                                            CrossAxisAlignment
                                                                .start,
                                                        children: [
                                                          Text(
                                                            srv.name,
                                                            style:
                                                                const TextStyle(
                                                              color:
                                                                  Colors.white,
                                                              fontSize: 13,
                                                              fontWeight:
                                                                  FontWeight
                                                                      .w600,
                                                            ),
                                                          ),
                                                          Text(
                                                            '${srv.cityName.isNotEmpty ? "${srv.cityName} • " : ""}${srv.stationIp}',
                                                            style:
                                                                const TextStyle(
                                                              color: Colors
                                                                  .white54,
                                                              fontSize: 11,
                                                            ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                    Container(
                                                      padding: const EdgeInsets
                                                          .symmetric(
                                                        horizontal: 8,
                                                        vertical: 3,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color: _loadColor(
                                                          srv.load,
                                                        ).withValues(alpha: 0.16),
                                                        borderRadius:
                                                            BorderRadius
                                                                .circular(8),
                                                      ),
                                                      child: Text(
                                                        'Tải ${srv.load}%',
                                                        style: TextStyle(
                                                          color: _loadColor(
                                                            srv.load,
                                                          ),
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w700,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
