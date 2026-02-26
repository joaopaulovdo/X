-- Tabela de Perfis
CREATE TABLE profiles (
  id UUID REFERENCES auth.users(id) PRIMARY KEY,
  email TEXT NOT NULL,
  full_name TEXT,
  role TEXT DEFAULT 'user',
  generated_count INTEGER DEFAULT 0,
  max_links INTEGER DEFAULT 10,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Tabela de QR Codes
CREATE TABLE qrcodes (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  code VARCHAR(5) UNIQUE NOT NULL,
  title TEXT,
  logo_url TEXT DEFAULT 'https://lh3.googleusercontent.com/d/1YGVDdCDIBYtl9iyZMm1A19DIc7QrTcv1',
  owner_id UUID REFERENCES profiles(id),
  target_url TEXT,
  status TEXT DEFAULT 'disponivel' CHECK (status IN ('disponivel', 'ativo', 'inativo')),
  scan_count INTEGER DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Configuração de Segurança (RLS)
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE qrcodes ENABLE ROW LEVEL SECURITY;

-- Políticas para profiles
CREATE POLICY "Perfis são visíveis para todos" ON profiles FOR SELECT USING (true);
CREATE POLICY "Usuários podem atualizar seu próprio perfil" ON profiles FOR UPDATE USING (auth.uid() = id);

-- Políticas para qrcodes
CREATE POLICY "QR Codes são visíveis para todos" ON qrcodes FOR SELECT USING (true);
CREATE POLICY "Usuários podem criar seus próprios códigos" ON qrcodes FOR INSERT WITH CHECK (
  auth.uid() = owner_id OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
);
CREATE POLICY "Usuários podem atualizar seus próprios códigos" ON qrcodes FOR UPDATE USING (
  owner_id = auth.uid() OR 
  (status = 'disponivel' AND owner_id IS NULL)
);
CREATE POLICY "Usuários podem excluir seus próprios códigos" ON qrcodes FOR DELETE USING (
  owner_id = auth.uid() OR
  EXISTS (SELECT 1 FROM profiles WHERE id = auth.uid() AND role = 'admin')
);

-- Trigger para criar perfil automaticamente após cadastro
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
BEGIN
  INSERT INTO public.profiles (id, email, full_name, role)
  VALUES (new.id, new.email, new.raw_user_meta_data->>'full_name', 'user');
  RETURN new;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.handle_new_user();

-- Função para incrementar scans de forma segura (permitindo acesso anônimo)
CREATE OR REPLACE FUNCTION increment_scan(qr_code VARCHAR)
RETURNS void AS $$
BEGIN
  UPDATE qrcodes
  SET scan_count = scan_count + 1
  WHERE code = qr_code;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
