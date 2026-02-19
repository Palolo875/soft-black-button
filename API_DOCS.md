# API Documentation

This document describes the external APIs used by HORIZON.

---

## 1. Valhalla (Routing)

**Base URL:** `https://valhalla1.openstreetmap.de`

### Endpoints

#### `POST /route`
Calculates a route between two or more locations.

**Request:**
```json
{
  "locations": [
    {"lat": 48.8566, "lon": 2.3522, "type": "break"},
    {"lat": 48.8606, "lon": 2.3376, "type": "break"}
  ],
  "costing": "bicycle",
  "directions_options": {"units": "kilometers"},
  "shape_format": "polyline6"
}
```

**Response:**
```json
{
  "trip": {
    "summary": {"length": 5.2, "time": 1200},
    "legs": [{"shape": "..."}]
  }
}
```

#### `GET /health`
Health check endpoint. Returns `200 OK` when service is available.

### Costing Options

| Mode | Costing | Description |
|------|---------|-------------|
| Cycling (Fast) | `bicycle` | Road bike, 24 km/h |
| Cycling (Safe) | `bicycle` | Hybrid, 18 km/h, avoid roads |
| Cycling (Scenic) | `bicycle` | City bike, 16 km/h |
| Walking | `pedestrian` | Standard walking |
| Car | `auto` | Standard driving |
| Motorbike | `motorcycle` | Motorcycle (falls back to auto) |

### Rate Limits
- No official rate limit documented
- Default: 2 attempts with exponential backoff
- Circuit breaker: 5 failures → 30s cooldown

### Environment Variables
```bash
VALHALLA_BASE_URL=https://valhalla1.openstreetmap.de
VALHALLA_TLS_PINS_B64=<base64-encoded-pem>
VALHALLA_ALLOW_HTTP=false
```

---

## 2. Open-Meteo (Weather - Primary)

**Base URL:** `https://api.open-meteo.com/v1/forecast`

### Endpoint

#### `GET /forecast`

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `latitude` | float | Latitude |
| `longitude` | float | Longitude |
| `hourly` | string | Variables (comma-separated) |
| `forecast_days` | int | Days (1-16, default 7) |

**Example:**
```
GET /v1/forecast?latitude=48.8566&longitude=2.3522&hourly=temperature_2m,apparent_temperature,precipitation,relativehumidity_2m,windspeed_10m,winddirection_10m&forecast_days=3
```

### Variables
- `temperature_2m` - Temperature at 2m
- `apparent_temperature` - Feels-like temperature
- `precipitation` - Precipitation (mm)
- `relativehumidity_2m` - Relative humidity (%)
- `windspeed_10m` - Wind speed (km/h)
- `winddirection_10m` - Wind direction (°)
- `cloudcover` - Cloud cover (%)
- `pressure_msl` - Pressure at sea level (hPa)

### Rate Limits
- **Free tier:** 1,000 requests/day
- No API key required for free tier

---

## 3. Met.no (Weather - Fallback)

**Base URL:** `https://api.met.no/weatherapi/locationforecast/2.0`

### Endpoint

#### `GET /compact`

**Headers Required:**
```
User-Agent: HORIZON/1.0 (+https://example.com/contact)
```

**Parameters:**
| Parameter | Type | Description |
|-----------|------|-------------|
| `lat` | float | Latitude |
| `lon` | float | Longitude |

**Example:**
```
GET /compact?lat=48.8566&lon=2.3522
```

### Rate Limits
- **Strict:** Must include valid User-Agent with contact info
- Recommends caching responses for 10+ minutes
- No API key required

### Terms of Service
- Requires descriptive User-Agent (contact info)
- Do not spam requests
- Cache aggressively

---

## 4. MapLibre / PMTiles (Offline Maps)

### Offline Map Tiles
- Format: PMTiles (Protocol Buffer)
- Source: Custom or OpenStreetMap exports
- Storage: App documents directory

### Tile Server (Optional)
If using custom vector tiles:
```
https://tiles.example.com/{z}/{x}/{y}.pmtiles
```

---

## Error Handling

### Circuit Breaker
All external APIs are protected by a circuit breaker:
- **Failure threshold:** 5 consecutive errors
- **Reset timeout:** 30 seconds
- **Half-open:** 2 successful requests to close

### Retry Strategy
- Valhalla: Exponential backoff (250ms, 500ms, 1000ms)
- Weather: Single retry on failure

### Fallback Chain
1. **Weather:** Open-Meteo → Met.no
2. **Routing:** Valhalla → Cache (offline mode)

---

## Security

### Certificate Pinning
Optional TLS pinning via `VALHALLA_TLS_PINS_B64` environment variable.

### HTTPS Only
All API calls enforce HTTPS by default (configurable via `allowHttp`).

---

## Caching Strategy

| Resource | TTL | Storage |
|----------|-----|---------|
| Weather | 15 min (30 min low-power) | Encrypted |
| Routes | 10 min (45 min low-power) | Encrypted |
| Offline Maps | Permanent | App storage |
