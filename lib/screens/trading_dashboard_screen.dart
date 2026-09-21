import 'package:flutter/material.dart';
import '../services/trading_service.dart';

class TradingDashboardScreen extends StatefulWidget {
  const TradingDashboardScreen({super.key});

  @override
  State<TradingDashboardScreen> createState() => _TradingDashboardScreenState();
}

class _TradingDashboardScreenState extends State<TradingDashboardScreen> {
  final _trading = const TradingService();
  int _tab = 0;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _account;
  List<dynamic> _markets = [];
  List<dynamic> _positions = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _trading.account(),
        _trading.markets(),
        _trading.positions(),
      ]);
      if (!mounted) return;
      setState(() {
        _account = results[0] as Map<String, dynamic>;
        _markets = results[1] as List<dynamic>;
        _positions = results[2] as List<dynamic>;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07100D),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('WILL TRADE', style: TextStyle(fontWeight: FontWeight.w900)),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? ListView(children: [
                    const SizedBox(height: 120),
                    Center(child: Text(_error!, textAlign: TextAlign.center)),
                    const SizedBox(height: 12),
                    Center(child: FilledButton(onPressed: _load, child: const Text('Retry'))),
                  ])
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 30),
                    children: [
                      _accountCard(),
                      const SizedBox(height: 18),
                      _tabs(),
                      const SizedBox(height: 16),
                      if (_tab == 0) ..._marketWidgets(),
                      if (_tab == 1) ..._positionWidgets(),
                      if (_tab == 2) _tradePanel(),
                    ],
                  ),
      ),
    );
  }

  Widget _accountCard() {
    final balance = _account?['balance']?.toString() ?? '0.00';
    final equity = _account?['equity']?.toString() ?? balance;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const LinearGradient(colors: [Color(0xFF123B2A), Color(0xFF0D1D17)]),
        border: Border.all(color: const Color(0xFF1F6D4A)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Portfolio value', style: TextStyle(color: Colors.white60)),
        const SizedBox(height: 5),
        Text('$$equity', style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w900)),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _metric('Cash', '$$balance')),
          Expanded(child: _metric('Positions', '${_positions.length}')),
        ]),
      ]),
    );
  }

  Widget _metric(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      const SizedBox(height: 3),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
    ],
  );

  Widget _tabs() => Row(children: [
    _tabButton('Markets', 0, Icons.show_chart),
    _tabButton('Positions', 1, Icons.account_balance_wallet_outlined),
    _tabButton('Trade', 2, Icons.swap_vert_rounded),
  ]);

  Widget _tabButton(String text, int index, IconData icon) {
    return Expanded(child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: ChoiceChip(
        selected: _tab == index,
        onSelected: (_) => setState(() => _tab = index),
        avatar: Icon(icon, size: 17),
        label: Text(text),
      ),
    ));
  }

  List<Widget> _marketWidgets() => [
    const Text('Markets', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
    const SizedBox(height: 8),
    ..._markets.map((m) => _marketTile(Map<String, dynamic>.from(m))),
  ];

  Widget _marketTile(Map<String, dynamic> market) {
    final symbol = market['symbol']?.toString() ?? '—';
    final price = market['price']?.toString() ?? '—';
    final change = market['changePercent']?.toString() ?? '0';
    return Card(
      color: const Color(0xFF101A16),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF173B2C),
          child: Text(symbol.substring(0, symbol.length.clamp(0, 1))),
        ),
        title: Text(symbol, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text('24h $change%'),
        trailing: Text('$$price', style: const TextStyle(fontWeight: FontWeight.w800)),
        onTap: () => setState(() => _tab = 2),
      ),
    );
  }

  List<Widget> _positionWidgets() => [
    const Text('Open positions', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
    const SizedBox(height: 8),
    if (_positions.isEmpty)
      const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('No open positions.')))
    else
      ..._positions.map((p) {
        final x = Map<String, dynamic>.from(p);
        return Card(
          color: const Color(0xFF101A16),
          child: ListTile(
            title: Text(x['symbol']?.toString() ?? '—'),
            subtitle: Text('Qty: ${x['qty'] ?? '—'}'),
            trailing: Text('${x['unrealizedPl'] ?? '—'}'),
          ),
        );
      }),
  ];

  Widget _tradePanel() {
    final symbol = TextEditingController(text: 'AAPL');
    final quantity = TextEditingController(text: '1');
    String side = 'buy';
    return StatefulBuilder(builder: (context, setLocal) => Card(
      color: const Color(0xFF101A16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('Place order', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
          const SizedBox(height: 14),
          TextField(controller: symbol, decoration: const InputDecoration(labelText: 'Symbol')),
          const SizedBox(height: 10),
          TextField(controller: quantity, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
          const SizedBox(height: 10),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'buy', label: Text('Buy')),
              ButtonSegment(value: 'sell', label: Text('Sell')),
            ],
            selected: {side},
            onSelectionChanged: (v) => setLocal(() => side = v.first),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              try {
                await _trading.placeOrder(
                  symbol: symbol.text.trim().toUpperCase(),
                  side: side,
                  quantity: quantity.text.trim(),
                  orderType: 'market',
                );
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Order submitted')));
                  await _load();
                }
              } catch (e) {
                if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
              }
            },
            child: const Text('Submit order'),
          ),
          const SizedBox(height: 8),
          const Text(
            'Orders are sent to your configured brokerage backend. Test with paper trading before enabling live execution.',
            style: TextStyle(color: Colors.white54, fontSize: 12),
          ),
        ]),
      ),
    ));
  }
}
