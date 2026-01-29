require 'csv'

class OntologyAnalyticsController < ApplicationController

  ##
  # get all ontology analytics for a given year/month combination
  namespace '/analytics' do

    get do
      expires 86400, :public
      year = year_param(params)
      error 400, 'The year you supplied is invalid. Valid years start with 2 and contain 4 digits.' if params['year'] && !year
      month = month_param(params)
      error 400, 'The month you supplied is invalid. Valid months are 1-12.' if params['month'] && !month
      acronyms = restricted_ontologies_to_acronyms(params)
      analytics = Ontology.analytics(year, month, acronyms)

      reply analytics
    end

  end

  ##
  # get all analytics for a given ontology
  namespace '/ontologies/:acronym/analytics' do

    get do
      expires 86400, :public
      ont = Ontology.find(params["acronym"]).first
      error 404, "No ontology exists with the acronym: #{params["acronym"]}" if ont.nil?
      year = year_param(params)
      error 400, "The year you supplied is invalid. Valid years start with 2 and contain 4 digits." if params["year"] && !year
      month = month_param(params)
      error 400, "The month you supplied is invalid. Valid months are 1-12." if params["month"] && !month
      analytics = ont.analytics(year, month)

      if params['format'].to_s.downcase.eql?("csv")
        tf = Tempfile.new("analytics-#{params['acronym']}")
        csv = CSV.new(tf, headers: true, return_headers: true, write_headers: true)
        csv << [:month, :visits]
        years = analytics[params["acronym"]].keys.sort
        now = Time.now
        years.each do |year|
          months = analytics[params["acronym"]][year].keys.sort
          months.each do |month|
            next if year && month && (now.year == year.to_i && now.month <= month.to_i || year.to_i == 2013 && month.to_i < 10) # we don't have good data going back past Oct 2013
            visits = analytics[params["acronym"]][year][month]
            month = DateTime.parse("#{year}/#{month}").strftime("%b %Y")
            csv << [month, visits]
          end
        end
        csv.close
        send_file tf.path, filename: "analytics-#{params['acronym']}.csv", type: 'text/csv', status: 200
      else
        reply analytics
      end
    end

  end

end
