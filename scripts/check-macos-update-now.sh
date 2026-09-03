#!/bin/bash
# Ouvre immédiatement l'interface Sparkle du compagnon Mac. Le contrôle
# automatique en arrière-plan reste volontairement cadencé toutes les 4 h.
set -euo pipefail

/usr/bin/open 'vibewalkie-mac://check-for-updates'
