class Object
  def reload_lib!
    Dir["#{Rails.root}/lib/*.rb"].map { |f| [f, load(f) ] } #.all? { |a| a[1] } 
    # Dir["#{Rails.root}/lib/**/*.rb"].map { |f| [f, load(f) ] } #.all? { |a| a[1] } 
    # uncomment above if you don't want to see all the reloaded files
  end
end