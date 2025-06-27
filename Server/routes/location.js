const express = require('express');
const router = express.Router();
const Location = require('../models/Location');

// POST /api/location
router.post('/location', async (req, res) => {
  try {
    const { user_id, start_location, end_location } = req.body;
    // Save both start and end locations if provided
    const locations = [];
    if (start_location) {
      locations.push(new Location({ user_id, latitude: start_location.latitude, longitude: start_location.longitude }));
    }
    if (end_location) {
      locations.push(new Location({ user_id, latitude: end_location.latitude, longitude: end_location.longitude }));
    }
    await Location.insertMany(locations);
    res.status(201).json({ success: true, locations });
  } catch (err) {
    res.status(400).json({ success: false, error: err.message });
  }
});

module.exports = router;
