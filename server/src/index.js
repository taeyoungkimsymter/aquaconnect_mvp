import 'dotenv/config';
import cors from 'cors';
import express from 'express';
import 'express-async-errors';

import { adminRouter } from './routes/admin.js';
import { authRouter } from './routes/auth.js';
import { diseaseInfoRouter } from './routes/diseaseInfo.js';
import { farmsRouter } from './routes/farms.js';
import { invitationsRouter, publicInvitationsRouter } from './routes/invitations.js';
import { scheduleAuditPurge } from './lib/audit.js';
import { scheduleDigests } from './lib/digest.js';
import { warmWaterQualityCache } from './lib/femo.js';
import { membersRouter } from './routes/members.js';
import { memosRouter } from './routes/memos.js';
import { scheduleNewsCollection } from './lib/news/collector.js';
import { newsRouter } from './routes/news.js';
import { notificationsRouter } from './routes/notifications.js';
import { oceanRouter } from './routes/ocean.js';
import { organizationRouter } from './routes/organization.js';
import { publicRouter } from './routes/public.js';
import { reportsRouter } from './routes/reports.js';
import { shareLinksRouter } from './routes/shareLinks.js';

const app = express();
app.use(cors());
// Memo photos arrive base64-encoded in the JSON body (up to 5 × 5MB).
app.use(express.json({ limit: '40mb' }));

app.get('/health', (req, res) => res.json({ ok: true }));

app.use('/api/auth', authRouter);
app.use('/api/farms', farmsRouter);
app.use('/api/memos', memosRouter);
app.use('/api/members', membersRouter);
app.use('/api/invitations', invitationsRouter);
app.use('/api/public/invitations', publicInvitationsRouter);
app.use('/api/organization', organizationRouter);
app.use('/api/notifications', notificationsRouter);
app.use('/api/disease-info', diseaseInfoRouter);
app.use('/api/news', newsRouter);
app.use('/api/reports', reportsRouter);
app.use('/api/share-links', shareLinksRouter);
app.use('/api/ocean', oceanRouter);
app.use('/api/public', publicRouter);
app.use('/api/admin', adminRouter);

// Keep this last: anything that throws inside a route (including a rejected
// promise from Express 4's own async wrapping) lands here instead of
// hanging the request.
app.use((err, req, res, next) => {
  console.error(err);
  res.status(500).json({ error: '서버 오류가 발생했습니다.' });
});

const port = process.env.PORT || 8080;
app.listen(port, () => console.log(`AquaConnect API listening on :${port}`));
scheduleAuditPurge();
scheduleDigests();
scheduleNewsCollection();
warmWaterQualityCache();
