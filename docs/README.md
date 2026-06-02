# Macs Bar Website

This directory contains the public website and update feed for **Macs Bar**, deployed automatically via GitHub Pages.

## 🛠️ Local Development

You can run and preview the website locally using Jekyll. This compiles all template layouts, processes Jekyll Liquid variables, and serves the fully built site.

1. Ensure you have `jekyll` installed globally.
2. In your terminal, navigate to the `docs` folder and run:

   ```bash
   jekyll serve
   ```

3. Open your browser and navigate to **[http://localhost:4000](http://localhost:4000)**.

## 📂 Directory Structure

- `_config.yml`: Core Jekyll configurations.
- `index.html`: The main landing page.
- `appcast.xml`: Sparkle feed for macOS app auto-updates.
- `assets/css/style.css`: Custom premium dark-mode stylesheet.

## 🚀 Deployment

The site is configured to deploy directly from the `/docs` folder of your `main` branch.
Any changes committed and pushed to `main` will be automatically built and published by GitHub Pages.
