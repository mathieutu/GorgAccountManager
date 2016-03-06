class Module::MergeController < ApplicationController

  require 'fuzzystringmatch'

  def user
    hruid = (params[:hruid].nil? ? params[:hruid].to_s : current_user.hruid)

    @user = User.find_by(:hruid => hruid)
    authorize! :read, @user

    @user_soce = Usersoce.where(hruid: hruid).take
    # info [titre, nom_du_champ, valeur_platal, valeur_soce, status {0=choix possible, 1=ok}]
    info_platal=get_info_from_platal(hruid)

    @info = [
      ["Identifiant", "hruid",   info_platal['hruid'],   @user_soce.hruid,     1],
      ["Prénom", "prenom",  formate_name(info_platal['firstname']),   @user_soce.prenom,     0],
      ["Nom", "nom",   formate_name(info_platal['lastname']),   @user_soce.nom,     0],
      ["Buque", "buktxt",  info_platal['buktxt'],  @user_soce.surnom,     0],
      ["Buque Zaloeil", "bukzal",  info_platal['bukzal'],  @user_soce.surnom,     0],
      ["Tabagn's", "centre1",  info_platal['tbk'],  @user_soce.centre1,     0],
      ["Email", "email",  info_platal['email'],  @user_soce.email,     0],
      ["Télephone portable", "tel_mobile",  info_platal['search_tel'],  @user_soce.tel_mobile,     0],
      ["Fam's", "famille1",  info_platal['gadz_fams'],  @user_soce.famille1,     0],
      ["Fam's Zaloeil", "famille1zal",  info_platal['gadz_fams_display'],  "choix2",     0],
      ["Date de naissance", "date_naissance",  info_platal['birthdate'],  @user_soce.date_naissance,     0],
      ["date_declaration_deces", "date_declaration_deces",  info_platal['deathdate'],  @user_soce.date_declaration_deces,     0]
    ]
    @addresses_soce=get_addresses_from_soce(hruid)

    addresses_soce_formated = @addresses_soce.map { |a| Geocoder.search(a.map(&:last)[0...-1].join(" ")).first.formatted_address }

    addresses_platal=get_addresses_from_platal(hruid)
    
    jarow = FuzzyStringMatch::JaroWinkler.create( :native )
    # retourne un tableau [ [tableau adresse soce], true si correspondace avec une adresse soce false sinon ]
    @addresses_platal=addresses_platal.map do |a| 
      [
      formate_address_soce(Geocoder.search(a["formatted_address"]).first), 
      addresses_soce_formated.map{ |b| jarow.getDistance(a["formatted_address"], b)}.max > 0.8,
      a["type"],
      case a["flags"]
      when /current/
        "(Principale)"
      when /secondary/
        "(Secondaire)"
      end
          
      ]
    end

    @jobs_platal = get_jobs_from_platal(hruid).sort_by{ |k| k["entry_year"]}.reverse
    @jobs_soce = get_jobs_from_soce(hruid)

  end

  def update_soce_user
  end

  def user_merged
  end

  private
    def get_info_from_platal(hruid)
      connection = OtherDatabaseConnection.establish_connection "platal_#{Rails.env}"

      sql = "select *, hruid, firstname, lastname, pgn.name as buktxt, pgn2.name as bukzal, email, gadz_fams, gadz_fams_display, birthdate, deathdate, search_tel, IF (tbk = 'kin', 'ai', tbk) as tbk
        from accounts as a
        left JOIN account_profiles AS ap ON (ap.uid=a.uid )
        left JOIN profiles AS p ON (p.pid=ap.pid) 
        right JOIN profile_gadz_names AS pgn ON (pgn.pid = p.pid and pgn.type = 'buktxt')
        right JOIN profile_gadz_names AS pgn2 ON (pgn2.pid = p.pid and pgn2.type = 'bukzal')
        left join group_members on a.uid = group_members.uid
        left join groups on group_members.asso_id = groups.id
        left join profile_phones on p.pid = profile_phones.pid
        left join profile_campus_enum on p.campus = profile_campus_enum.id
        where groups.cat = 'Promotions'
        and tel_type = 'mobile'
        and link_type = 'user'
        and hruid = '#{hruid}'"
      @result = connection.connection.execute(sql);
      @result.each(:as => :hash) do |row| 
        row["user"] 
      end
      connection.disconnect!
      @result.first

    end

    def get_addresses_from_platal(hruid)
      connection = OtherDatabaseConnection.establish_connection "platal_#{Rails.env}"

      sql = "select formatted_address, postalText, pa.type, pa.flags
        from accounts as a
        left JOIN account_profiles AS ap ON (ap.uid=a.uid )
        left JOIN profile_addresses AS pa ON (pa.pid=ap.pid)
        where hruid = '#{hruid}'"
      @result = connection.connection.execute(sql);
            connection.disconnect!

      @result.each(:as => :hash) do |row| 
        row["adresses"] 
      end

    end
    def get_jobs_from_platal(hruid)
      connection = OtherDatabaseConnection.establish_connection "platal_#{Rails.env}"

      sql = "select pj.description AS job_desc, pj.email, pj.url AS job_url, entry_year, pje.name AS cpny_name, pje.url, NAF_code, pje.description AS cpny_desc, jte.name, jte.full_name
        from accounts as a
        left JOIN account_profiles AS ap ON (ap.uid=a.uid )
        left JOIN profile_job AS pj ON (pj.pid=ap.pid)
        left JOIN profile_job_enum AS pje ON (pje.id=pj.jobid)
        left JOIN profile_job_term AS jt  ON (jt.pid = pj.pid AND jt.jid = pj.id)
        LEFT JOIN  profile_job_term_enum AS jte USING(jtid)
        where hruid = '#{hruid}'"
      @result = connection.connection.execute(sql);
            connection.disconnect!

      @result.each(:as => :hash) do |row| 
        row["jobs"] 
      end

    end


    

    def get_addresses_from_soce(hruid)
      connection = OtherDatabaseConnection.establish_connection "soce_#{Rails.env}"

      sql = "SELECT adresse_1, adresse_2, code_postal, ville, nompays, adt.libelle  FROM users AS u
        left JOIN adresses AS ad ON (u.id_user=ad.id_user )
        left JOIN pays AS py ON (py.id_pays=ad.id_pays )
        left JOIN liste_adresse_types AS adt ON (adt.id_adresse_type=ad.id_adresse_type )
        where hruid = '#{hruid}'"
      @result = connection.connection.execute(sql);
            connection.disconnect!

      @result.each(:as => :hash) do |row| 
        row["adresses"] 
      end

    end

    def get_jobs_from_soce(hruid)
      connection = OtherDatabaseConnection.establish_connection "soce_#{Rails.env}"

      sql = "SELECT e.*, p.date_debut, p.date_fin, p.tel_direct, p.tel_standard, p.email, p.gsm, p.adresse, p.adresse2, p.adresse3, p.code_postal AS code_postal_entreprise, p.ville AS ville_entreprise, p.pays AS pays_entreprise, p.fax, p.id_etat_validation
, py.*, f.* FROM users 
left join postes AS p on users.id_user = p.id_user
left join entreprises AS e on e.id_entreprise = p.id_entreprise
left join pays AS py on e.id_pays = py.id_pays
left join liste_fonctions AS f on f.id_fonction = p.id_fonction
        where hruid = '#{hruid}'"
      @result = connection.connection.execute(sql);
            connection.disconnect!

      @result.each(:as => :hash) do |row| 
        row["jobs"] 
      end

    end


    # Capitalize firt letter for name. Work even with composed name
    #  "Jean-Paul du bou'd'larue" devient "Jean-Paul Du Bou'd'Larue"
    #  "Jean d'uboudlarue" devient "Jean d'Uboudlarue"
    def formate_name(name)
      # name.split.map{|p| p.split("-").map{|m| m.split("'").map{|n| (n.length > 1 ? n.capitalize : n) }.join("'")}.join("-")}.join(" ")
      name.gsub(/[^\s\-']{02,}/, &:capitalize)

    end


    # Formate le numero de téléphone au format la soce "06.12.34.56.78"
    def formate_phone_for_soce(phone)
      if phone[0..1] ="33"
        formated_phone =  ("0"+phone[2..phone.length]).scan(/../).join(".")
      else
        formated_phone =  ("0"+phone[2..phone.length]).scan(/../).join(".")
      end
    end

    def formate_address_soce(address)
      addresss1 = [
        ( begin address.address_components.select{|n| n["types"].include? "street_number"}.first["long_name"] rescue "" end),
        ( begin address.address_components.select{|n| n["types"].include? "route"}.first["long_name"] rescue "" end)

      ].join(" ")

      addresss2 =""
      postal_code = ( begin address.address_components.select{|n| n["types"].include? "postal_code"}.first["long_name"] rescue "" end )
      city = ( begin address.address_components.select{|n| n["types"].include? "locality"}.first["long_name"] rescue "" end )
      country = ( begin address.address_components.select{|n| n["types"].include? "country"}.first["long_name"] rescue "" end )

      return [addresss1, addresss2, postal_code, city, country]

    end
end