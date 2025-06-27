const express = require('express');
const router = express.Router();
const User = require('../models/User');

// POST /api/login
router.post('/login', async (req, res) => {
  try {
    const { username, password } = req.body;
    const user = await User.findOne({ username, password });
    if (!user) return res.status(401).json({ success: false, error: 'Invalid credentials' });
    res.json({ success: true, user: { id: user._id, username: user.username, role: user.role } });
  } catch (err) {
    res.status(500).json({ success: false, error: err.message });
  }
});

module.exports = router;
