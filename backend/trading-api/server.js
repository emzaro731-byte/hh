import express from 'express';
import cors from 'cors';

const app = express();
app.use(cors());
app.use(express.json());

const PORT = process.env.PORT || 8080;
const ALPACA_BASE_URL = process.env.ALPACA_BASE_URL || 'https://paper-api.alpaca.markets';
const ALPACA_KEY = process.env.ALPACA_API_KEY;
const ALPACA_SECRET = process.env.ALPACA_API_SECRET;

function authHeaders() {
  if (!ALPACA_KEY || !ALPACA_SECRET) throw new Error('Missing ALPACA_API_KEY or ALPACA_API_SECRET');
  return {
    'APCA-API-KEY-ID': ALPACA_KEY,
    'APCA-API-SECRET-KEY': ALPACA_SECRET,
    'Content-Type': 'application/json',
  };
}

async function alpaca(path, options = {}) {
  const response = await fetch(`${ALPACA_BASE_URL}${path}`, {
    ...options,
    headers: { ...authHeaders(), ...(options.headers || {}) },
  });
  const text = await response.text();
  let data;
  try { data = JSON.parse(text); } catch { data = { message: text }; }
  if (!response.ok) {
    const error = new Error(data?.message || `Broker error ${response.status}`);
    error.status = response.status;
    throw error;
  }
  return data;
}

app.get('/health', (_, res) => res.json({ ok: true, service: 'will-trade-api' }));

app.get('/api/account', async (_, res) => {
  try {
    const a = await alpaca('/v2/account');
    res.json({ id: a.id, status: a.status, currency: a.currency, balance: a.cash, equity: a.equity });
  } catch (e) { res.status(e.status || 500).json({ error: e.message }); }
});

app.get('/api/account/positions', async (_, res) => {
  try {
    const positions = await alpaca('/v2/positions');
    res.json({ positions: positions.map(p => ({
      symbol: p.symbol, qty: p.qty, marketValue: p.market_value, unrealizedPl: p.unrealized_pl
    }))});
  } catch (e) { res.status(e.status || 500).json({ error: e.message }); }
});

app.get('/api/markets', async (_, res) => {
  try {
    const symbols = ['AAPL', 'TSLA', 'NVDA', 'AMZN', 'MSFT'];
    const quotes = await Promise.all(symbols.map(async symbol => {
      try {
        const q = await alpaca(`/v2/stocks/${symbol}/quotes/latest`);
        const price = Number(q.quote?.ap || q.quote?.bp || 0);
        return { symbol, price, changePercent: 0 };
      } catch {
        return { symbol, price: 0, changePercent: 0 };
      }
    }));
    res.json({ markets: quotes });
  } catch (e) { res.status(e.status || 500).json({ error: e.message }); }
});

app.get('/api/quote/:symbol', async (req, res) => {
  try {
    const symbol = req.params.symbol.toUpperCase();
    const q = await alpaca(`/v2/stocks/${encodeURIComponent(symbol)}/quotes/latest`);
    res.json(q);
  } catch (e) { res.status(e.status || 500).json({ error: e.message }); }
});

app.post('/api/orders', async (req, res) => {
  try {
    const { symbol, side, quantity, type = 'market', timeInForce = 'day' } = req.body || {};
    if (!symbol || !['buy', 'sell'].includes(side) || !quantity) {
      return res.status(400).json({ error: 'symbol, side and quantity are required' });
    }
    const order = await alpaca('/v2/orders', {
      method: 'POST',
      body: JSON.stringify({ symbol, side, qty: String(quantity), type, time_in_force: timeInForce }),
    });
    res.status(201).json({
      id: order.id, symbol: order.symbol, side: order.side, qty: order.qty,
      status: order.status, type: order.type,
    });
  } catch (e) { res.status(e.status || 500).json({ error: e.message }); }
});

app.listen(PORT, () => console.log(`will-trade-api listening on :${PORT}`));
