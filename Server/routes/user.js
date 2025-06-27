const express = require('express');
const router = express.Router();
const User = require('../models/User');

// GET /api/get_users_by_date?start=YYYY-MM-DD&end=YYYY-MM-DD
router.get('/get_users_by_date', async (req, res) => {
  try {
    const { start, end } = req.query;
    if (!start || !end) return res.status(400).json({ error: 'Start and end dates required' });
    const startDate = new Date(start);
    const endDate = new Date(end);
    endDate.setHours(23, 59, 59, 999); // include the whole end day
    const users = await User.find({ createdAt: { $gte: startDate, $lte: endDate } });
    res.json({ success: true, users });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/get_users
router.get('/get_users', async (req, res) => {
  try {
    const users = await User.find();
    res.json({ success: true, users });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// GET /api/get_user_details?user_id=...
router.get('/get_user_details', async (req, res) => {
  try {
    const user = await User.findById(req.query.user_id);
    if (!user) return res.status(404).json({ success: false, error: 'User not found' });
    res.json({ success: true, user });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

// POST /api/add_user
router.post('/add_user', async (req, res) => {
  try {
    const { username, password, role } = req.body;
    const user = new User({ username, password, role });
    await user.save();
    res.status(201).json({ success: true, user });
  } catch (err) {
    res.status(400).json({ success: false, error: err.message });
  }
});

// PUT /api/update_user
router.put('/update_user', async (req, res) => {
  try {
    const { user_id, ...update } = req.body;
    const user = await User.findByIdAndUpdate(user_id, update, { new: true });
    if (!user) return res.status(404).json({ success: false, error: 'User not found' });
    res.json({ success: true, user });
  } catch (err) {
    res.status(400).json({ success: false, error: err.message });
  }
});

module.exports = router;
