-- Social feed tables: likes and comments on sessions

CREATE TABLE public.session_likes (
  session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  PRIMARY KEY (session_id, user_id)
);
ALTER TABLE public.session_likes ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read likes" ON public.session_likes FOR SELECT USING (true);
CREATE POLICY "Users manage own likes" ON public.session_likes FOR ALL USING (auth.uid() = user_id);

CREATE TABLE public.session_comments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id UUID NOT NULL REFERENCES public.sessions(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  body TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);
ALTER TABLE public.session_comments ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Anyone can read comments" ON public.session_comments FOR SELECT USING (true);
CREATE POLICY "Users manage own comments" ON public.session_comments FOR ALL USING (auth.uid() = user_id);
