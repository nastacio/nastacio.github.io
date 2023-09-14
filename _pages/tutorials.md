---
layout: archive
title: "Tutorials"
permalink: /tutorials/
author_profile: false
paginator: true
---

<h3 class="archive__subtitle">{{ site.data.ui-text[site.locale].recent_posts | default: "Recent Posts" }}</h3>

{% if paginator %}
  {% assign posts = paginator.posts %}
{% else %}
  {% assign posts = site.posts %}
{% endif %}

{% assign entries_layout = page.entries_layout | default: 'list' %}
<div class="entries-{{ entries_layout }}">
  {% for post in posts %}
    {% if post.category contains "tutorial" %}
      {% include archive-single.html type=entries_layout %}
    {% endif %}
  {% endfor %}
</div>
