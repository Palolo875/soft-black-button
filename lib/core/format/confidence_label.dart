String confidenceLabelFr(double confidence) {
  if (confidence >= 0.75) return 'Fiable';
  if (confidence >= 0.50) return 'Variable';
  return 'Incertain';
}
