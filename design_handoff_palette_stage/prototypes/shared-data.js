// Shared mock data for all 5 Tanque Studio layout concepts.
// Plain JS (no JSX) — load before each concept's babel script with a normal <script src>.
window.TD = {

  navItems: [
    { id: 'generate',        label: 'Generate',           icon: 'brush',  labs: false },
    { id: 'dtProjects',      label: 'DT Project Browser',  icon: 'folder', labs: false },
    { id: 'storyFlow',       label: 'StoryFlow',           icon: 'film',   labs: true  },
    { id: 'storyStudio',     label: 'Story Studio',        icon: 'spark',  labs: true  },
    { id: 'workflowBuilder', label: 'Workflow Builder',    icon: 'flow',   labs: true  },
    { id: 'settings',        label: 'Settings',            icon: 'gear',   labs: false },
  ],

  models: [
    { id: 'flux1-dev-q4',    name: 'flux.1 [dev]',      variant: 'Q4 · gguf',        family: 'FLUX',  swatch: ['#5a4a3a', '#c9a058'] },
    { id: 'flux1-schnell',   name: 'flux.1 [schnell]',  variant: 'Q8 · gguf',        family: 'FLUX',  swatch: ['#3a4a5a', '#5aafaa'] },
    { id: 'flux2-klein-4b',  name: 'flux.2 [klein]',    variant: '4b · Q6 K',        family: 'FLUX',  swatch: ['#4a3a5a', '#9580b8'] },
    { id: 'sd35-large',      name: 'SD 3.5 Large',      variant: 'Q4 · gguf',        family: 'SD',    swatch: ['#5a3a3a', '#d05f5f'] },
    { id: 'dreamshaper-xl',  name: 'DreamShaper XL',    variant: 'v2 turbo',         family: 'SDXL',  swatch: ['#3a5a4a', '#4caf7a'] },
  ],

  samplers: ['DPM++ 2M', 'Euler a', 'DPM++ SDE', 'DDIM', 'LMS'],
  aspects: ['1:1', '4:3', '3:4', '16:9', '9:16', '3:2', '2:3'],

  loras: [
    { id: 'l1', name: 'cinematic-grain-v3', weight: 0.65 },
    { id: 'l2', name: 'soft-portrait-lora', weight: 0.40 },
  ],

  gallery: [
    { id: 1, source: 'generated', label: '2s ago',  prompt: 'labradoodle puppy, yellow bandana, sunlit studio' },
    { id: 2, source: 'generated', label: '3m ago',  prompt: 'cliffside lighthouse at dusk, long exposure' },
    { id: 3, source: 'imported',  label: 'imported', prompt: '(imported PNG — no prompt recorded)' },
    { id: 4, source: 'generated', label: '12m ago', prompt: 'macro shot of dew on spider web, morning light' },
    { id: 5, source: 'generated', label: '1h ago',  prompt: 'isometric cozy cabin, snow, warm windows' },
    { id: 6, source: 'generated', label: '2h ago',  prompt: 'oil painting, orchard in autumn, wide brushstrokes' },
  ],

  metadata: [
    ['Model', 'flux1-dev-Q4.gguf'],
    ['Steps', '20'],
    ['CFG', '7.5'],
    ['Seed', '42'],
    ['Sampler', 'DPM++ 2M'],
    ['Size', '1024 × 1024'],
    ['Strength', '1.0'],
    ['Duration', '18.3s'],
  ],

  dtProjects: [
    { id: 'p1', name: 'portrait-series-04.sqlite3',  images: 142, updated: '2 days ago' },
    { id: 'p2', name: 'landscape-explorations.sqlite3', images: 58, updated: '1 week ago' },
    { id: 'p3', name: 'client-moodboard-acme.sqlite3', images: 23, updated: '3 weeks ago' },
    { id: 'p4', name: 'character-turnaround.sqlite3', images: 87, updated: '1 month ago' },
  ],

  storyFlowSteps: [
    { id: 's1', title: 'Establish scene',    kind: 'generate', status: 'done' },
    { id: 's2', title: 'Character close-up', kind: 'generate', status: 'done' },
    { id: 's3', title: 'Add rain overlay',   kind: 'transform', status: 'active' },
    { id: 's4', title: 'Final grade',        kind: 'llm', status: 'pending' },
  ],

  actions: [
    { label: 'Send All',         sub: 'Apply prompt, negative, and full config' },
    { label: 'Send Prompt',      sub: 'Apply prompt and negative only' },
    { label: 'Send Config',      sub: 'Apply model, sampler, steps, LoRAs' },
    { label: 'Send to img2img',  sub: 'Set current image as source' },
    { label: 'Add to Moodboard', sub: 'Add to reference strip' },
  ],
};
