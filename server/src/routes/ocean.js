import { Router } from 'express';

import { fetchRealtimeObservations } from '../lib/nifs.js';
import { fetchRedTide } from '../lib/redtide.js';

export const oceanRouter = Router();

// No auth: this just mirrors the public NIFS feed, and having it open makes
// it trivial to sanity-check the proxy is alive after a Railway deploy.
oceanRouter.get('/realtime', async (req, res) => {
  try {
    const observations = await fetchRealtimeObservations({ station: req.query.station });
    res.json(observations);
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});

// Newest NIFS 적조 속보 (with its detail text) and the recent ones.
// `refresh=1` bypasses the server cache.
oceanRouter.get('/redtide', async (req, res) => {
  try {
    res.json(await fetchRedTide({ refresh: req.query.refresh === '1' || req.query.refresh === 'true' }));
  } catch (err) {
    res.status(502).json({ error: err.message });
  }
});
