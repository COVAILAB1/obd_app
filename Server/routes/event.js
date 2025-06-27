const express = require('express');
const router = express.Router();
const Event = require('../models/Event');

// GET /api/get_events?user_id=...
router.get('/get_events', async (req, res) => {
  try {
    const events = await Event.find({ user_id: req.query.user_id });
    res.json({ success: true, events });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /api/log_event
router.post('/log_event', async (req, res) => {
  try {
    const { user_id, event_type, event_description, timestamp, speed_obd, speed_gps, latitude, longitude } = req.body;
    const event = new Event({
      user_id,
      type: event_type,
      details: { event_description, speed_obd, speed_gps, latitude, longitude },
      timestamp: timestamp ? new Date(timestamp) : Date.now(),
    });
    await event.save();
    res.status(201).json({ success: true, event });
  } catch (err) {
    res.status(400).json({ success: false, error: err.message });
  }
});

module.exports = router;
