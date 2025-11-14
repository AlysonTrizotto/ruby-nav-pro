# Exemplo para testar a nova funcionalidade de contexto

class User
  def initialize(name)
    @name = name
  end
  
  def greet
    "Hello, #{@name}!"
  end
  
  def save
    puts "Saving user..."
  end
end

class Product
  def initialize(name)
    @name = name
  end
  
  def save
    puts "Saving product..."
  end
end

# Teste de contexto - ao clicar em 'save' aqui:
user = User.new("John")
user.save  # Deve ir para User#save, não Product#save

product = Product.new("Book") 
product.save  # Deve ir para Product#save, não User#save

# Teste de constantes
class Admin::User < User
  def admin_save
    save  # Deve entender que é o save do User (herança)
  end
end

# Teste de métodos de classe
class StringUtil
  def self.format(text)
    text.upcase
  end
end

# Ao clicar em 'format' aqui:
StringUtil.format("hello")  # Deve ir para StringUtil.format