#!/usr/bin/env bash
npm run project-setup
npm install
hugo server --bind 0.0.0.0 --poll 700ms
