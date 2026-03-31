-- Enable Realtime for echoes and handles tables
ALTER PUBLICATION supabase_realtime ADD TABLE public.echoes;
ALTER PUBLICATION supabase_realtime ADD TABLE public.handles;
